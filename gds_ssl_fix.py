"""
GDS SSL/TLS workaround for requests certificate verification issues.

This module applies environment-level fixes to disable SSL verification
for api.neo4j.io when connecting from certain Python/OpenSSL combinations
that have TLS handshake issues.

Usage:
    import gds_ssl_fix  # Must be before importing graphdatascience
    from graphdatascience.session import GdsSessions
    ...
"""

import os
import urllib3
import requests


def patch_gds_ssl():
    """Apply environment-level SSL workarounds for GDS Aura API calls."""

    # Disable SSL verification globally for this process
    # This is a workaround for SSLEOFError on certain Python/OpenSSL versions
    os.environ['REQUESTS_CA_BUNDLE'] = ''
    os.environ['CURL_CA_BUNDLE'] = ''

    # Disable urllib3 SSL warnings
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

    # Force requests calls to Aura API host to skip SSL verification.
    original_request = requests.sessions.Session.request

    def patched_request(self, method, url, *args, **kwargs):
        if isinstance(url, str) and url.startswith('https://api.neo4j.io'):
            kwargs.setdefault('verify', False)
        return original_request(self, method, url, *args, **kwargs)

    requests.sessions.Session.request = patched_request

    # Monkey-patch urllib3 to ignore SSL verification
    try:
        from urllib3.contrib import pyopenssl
        pyopenssl.inject_into_urllib3()
    except Exception:
        pass

    # Patch graphdatascience AuraApi to accept and use verify=False
    try:
        import graphdatascience.session.aura_api as aura_api_module

        # Get the original AuraApi class
        original_auraapi = aura_api_module.AuraApi

        class PatchedAuraApi(original_auraapi):
            """Patched AuraApi class that disables SSL verification."""

            def __init__(self, client_id, client_secret, project_id=None, aura_env=None, ssl_verify=False):
                super().__init__(client_id, client_secret, project_id, aura_env)
                self.ssl_verify = ssl_verify

                # Disable SSL verification in the underlying requests session
                if not ssl_verify:
                    # Patch the Auth class to use verify=False
                    original_update_token = self._api.Auth._update_token

                    def patched_update_token(self):
                        data = {"grant_type": "client_credentials"}
                        self._logger.debug("Updating oauth token (SSL verification disabled)")

                        resp = self._request_session.post(
                            self._oauth_url,
                            data=data,
                            auth=(self._credentials[0], self._credentials[1]),
                            verify=False  # Explicitly disable SSL verification
                        )

                        if resp.status_code >= 400:
                            from graphdatascience.session.aura_api import AuraApiError
                            raise AuraApiError(
                                "Failed to authorize with provided client credentials: "
                                + f"{resp.status_code} - {resp.reason}, {resp.text}",
                                status_code=resp.status_code,
                            )

                        token = self._token_class_type(resp.json())
                        return token

                    self._api.Auth._update_token = patched_update_token

        # Replace the class
        aura_api_module.AuraApi = PatchedAuraApi

        print("✓ GDS SSL workaround applied: SSL certificate verification disabled for api.neo4j.io")

    except Exception as e:
        print(f"⚠ Could not apply GDS patch (but continuing): {type(e).__name__}: {e}")


# Auto-apply the patch when this module is imported
patch_gds_ssl()
