# BYOID (External Account) Live Integration Testing Guide

This guide explains how to configure and execute live integration tests for the **Bring Your Own Identity (BYOID) / External Account Credentials** implementation in `GoogleCloudAuth` (`packages/swift-google-auth`).

______________________________________________________________________

## 1. Overview & Architecture

Google Cloud Workload and Workforce Identity Federation allows applications to authenticate to Google Cloud APIs using external identity providers (OIDC, SAML, AWS, Apple ID) without long-lived service account keys ([AIP-4117](https://google.aip.dev/auth/4117)).

In the programmatic external account flow, the SDK delegates third-party identity token retrieval to a `SubjectTokenProvider` callback, then exchanges that token with Google's Security Token Service (STS) at `https://sts.googleapis.com/v1/token` for a short-lived Google Cloud access token (`Bearer ya29...`).

```text
┌───────────────────────────────────────────────────────────┐
│                    Integration Test                       │
└─────────────┬───────────────────────────────┬─────────────┘
              │ 1. gcloud auth                │ 2. SubjectTokenProvider
              │    print-identity-token       │
              ▼                               ▼
┌───────────────────────────┐   ┌───────────────────────────┐
│ Google Cloud IAM          │   │ GoogleCloudAuth           │
│ (accounts.google.com)     │   │ (ExternalAccountCreds)    │
└─────────────┬─────────────┘   └─────────────┬─────────────┘
              │ Returns raw ID token (JWT)    │ 3. POST /v1/token
              └──────────────────────────────►│    grant_type=token-exchange
                                              ▼
                                ┌───────────────────────────┐
                                │ Google STS                │
                                │ (sts.googleapis.com)      │
                                └─────────────┬─────────────┘
                                              │ Returns TokenResponse
                                              ▼
                                ┌───────────────────────────┐
                                │ Access Token              │
                                │ (Bearer ya29...)          │
                                └───────────────────────────┘
```

______________________________________________________________________

## 2. Test Environment

Tests run against the pre-provisioned test project:

- **Project ID**: `rust-external-account-joonix`
- **Project Number**: `1092239828259`
- **Workload Identity Pool**: `google-idp`
- **Workload Identity Provider**: `google-idp` (trusts issuer `https://accounts.google.com`)
- **Audience URI**: `//iam.googleapis.com/projects/1092239828259/locations/global/workloadIdentityPools/google-idp/providers/google-idp`
- **Service Account**: `testsa@rust-external-account-joonix.iam.gserviceaccount.com`

______________________________________________________________________

## 3. Prerequisites & One-Time Setup

### 3.1 Verify Access to the Test Project

Ensure your local `gcloud` CLI is authenticated and has access to the test project:

```bash
gcloud projects describe rust-external-account-joonix
```

Verify that the workload identity pool and provider exist:

```bash
gcloud iam workload-identity-pools describe google-idp \
    --project="rust-external-account-joonix" \
    --location="global"

gcloud iam workload-identity-pools providers describe google-idp \
    --project="rust-external-account-joonix" \
    --workload-identity-pool="google-idp" \
    --location="global"
```

### 3.2 Grant Token Creator Permission

To allow your user account to generate OIDC ID tokens via service account impersonation, bind the `roles/iam.serviceAccountTokenCreator` role on `testsa`:

```bash
USER_EMAIL=$(gcloud config get-value account)

gcloud iam service-accounts add-iam-policy-binding \
    testsa@rust-external-account-joonix.iam.gserviceaccount.com \
    --project="rust-external-account-joonix" \
    --role="roles/iam.serviceAccountTokenCreator" \
    --member="user:${USER_EMAIL}"
```

### 3.3 Verify Token Generation

Test generating a test ID token:

```bash
gcloud auth print-identity-token \
    --audiences="//iam.googleapis.com/projects/1092239828259/locations/global/workloadIdentityPools/google-idp/providers/google-idp" \
    --impersonate-service-account="testsa@rust-external-account-joonix.iam.gserviceaccount.com"
```

The output should be a raw JWT starting with `eyJ...`.

______________________________________________________________________

## 4. Running the Integration Tests

### 4.1 Required Environment Variables

The integration tests check for the presence of the following environment variables. If they are not set, the tests are safely skipped:

| Variable | Description | Example Value |
| :--- | :--- | :--- |
| `GOOGLE_CLOUD_PROJECT` | GCP Project ID | `rust-external-account-joonix` |
| `GOOGLE_WORKLOAD_IDENTITY_OIDC_AUDIENCE` | Full Identity Provider Audience URI | `//iam.googleapis.com/projects/1092239828259/locations/global/workloadIdentityPools/google-idp/providers/google-idp` |
| `EXTERNAL_ACCOUNT_SERVICE_ACCOUNT_EMAIL` | Impersonated Service Account Email | `testsa@rust-external-account-joonix.iam.gserviceaccount.com` |

### 4.2 Execute the Test

Run the targeted integration test suite with the environment variables exported:

```bash
GOOGLE_CLOUD_PROJECT="rust-external-account-joonix" \
GOOGLE_WORKLOAD_IDENTITY_OIDC_AUDIENCE="//iam.googleapis.com/projects/1092239828259/locations/global/workloadIdentityPools/google-idp/providers/google-idp" \
EXTERNAL_ACCOUNT_SERVICE_ACCOUNT_EMAIL="testsa@rust-external-account-joonix.iam.gserviceaccount.com" \
swift test --package-path packages/swift-google-auth --filter ExternalAccountGoogleCloudIntegrationTests
```

### 4.3 Expected Output

```text
◇ Suite "External Account Google Cloud Live OIDC Integration Tests" started.
◇ Test "Generates IAM OIDC ID token, exchanges via STS, and verifies access token" started.
✔ Test "Generates IAM OIDC ID token, exchanges via STS, and verifies access token" passed after 2.092 seconds.
✔ Suite "External Account Google Cloud Live OIDC Integration Tests" passed after 2.093 seconds.
✔ Test run with 1 test in 1 suite passed after 2.093 seconds.
```

______________________________________________________________________

## 5. What the Integration Test Validates

The test (`ExternalAccountGoogleCloudIntegrationTests.swift`):

1. Invokes `gcloud auth print-identity-token` dynamically with the configured audience and impersonated service account to obtain a fresh OIDC ID token (JWT).
1. Instantiates `ExternalAccountCredentials` using the programmatic credential source and the returned subject token.
1. Invokes `creds.headers()` to trigger a live HTTP POST exchange with Google STS (`https://sts.googleapis.com/v1/token`).
1. Asserts that the response headers contain an `Authorization` header with a valid Google Cloud access token starting with `Bearer ya29.`.
1. Also instantiates the top-level public `Credentials(configuration: .programmaticExternalAccount(config))` entry point and verifies that public API resolution succeeds.

______________________________________________________________________

## 6. Troubleshooting & Common Pitfalls

| Error / Symptom | Root Cause | Solution |
| :--- | :--- | :--- |
| `PERMISSION_DENIED: Failed to impersonate testsa` | Missing `roles/iam.serviceAccountTokenCreator` binding on `testsa`. | Re-run Section 3.2 to grant the role to your authenticated gcloud user account. |
| STS HTTP 400: `Invalid value for "audience"` | Audience resource name misspelling (e.g., using `workloadPools` instead of `workloadIdentityPools`). | Workload Identity Federation uses `//iam.googleapis.com/projects/<NUM>/locations/global/workloadIdentityPools/<POOL>/providers/<PROV>`. Ensure `workloadIdentityPools` is used. |
| STS HTTP 400: `Scope(s) must be provided` | Scopes parameter omitted during token exchange. | In `GoogleCloudAuth`, scopes default to `["https://www.googleapis.com/auth/cloud-platform"]` per AIP-4117. Ensure non-empty scopes are provided if overriding. |
| Test skipped with message `Skipping M1 test: Missing required environment variables` | Required environment variables were not set in the shell running `swift test`. | Export `GOOGLE_CLOUD_PROJECT`, `GOOGLE_WORKLOAD_IDENTITY_OIDC_AUDIENCE`, and `EXTERNAL_ACCOUNT_SERVICE_ACCOUNT_EMAIL` prior to executing the test. |
