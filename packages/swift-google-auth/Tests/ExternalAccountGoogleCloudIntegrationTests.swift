// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import Testing
@testable import GoogleCloudAuth

private struct StaticSubjectTokenProvider: SubjectTokenProvider {
  let token: String

  func subjectToken() async throws -> String {
    return token
  }
}

@Suite("External Account Google Cloud Live OIDC Integration Tests")
struct ExternalAccountGoogleCloudIntegrationTests {
  @Test("Generates IAM OIDC ID token, exchanges via STS, and verifies access token")
  func testProgrammaticGoogleCloudOIDCSTSExchange() async throws {
    guard let project = ProcessInfo.processInfo.environment["GOOGLE_CLOUD_PROJECT"],
      let audience = ProcessInfo.processInfo.environment["GOOGLE_WORKLOAD_IDENTITY_OIDC_AUDIENCE"],
      let saEmail = ProcessInfo.processInfo.environment["EXTERNAL_ACCOUNT_SERVICE_ACCOUNT_EMAIL"],
      !project.isEmpty
    else {
      print("Skipping M1 test: Missing required environment variables")
      return
    }

    // 1. Generate a fresh OIDC ID token via gcloud / IAM
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    var env = ProcessInfo.processInfo.environment
    let currentPath = env["PATH"] ?? ""
    env["PATH"] =
      "\(currentPath):/Users/neastin/google-cloud-sdk/bin:/usr/local/bin:/opt/homebrew/bin"
    process.environment = env
    process.arguments = [
      "gcloud", "auth", "print-identity-token",
      "--audiences=\(audience)",
      "--impersonate-service-account=\(saEmail)",
    ]
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe
    try process.run()
    process.waitUntilExit()

    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    guard
      let idToken = String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(
        in: .whitespacesAndNewlines),
      !idToken.isEmpty, !idToken.contains("ERROR")
    else {
      let err = String(data: stderrData, encoding: .utf8) ?? ""
      Issue.record("Failed to obtain ID token from IAM: \(err)")
      return
    }

    // 2. Configure Programmatic External Account Credentials
    let creds = try ExternalAccountCredentials(
      credentialSource: .programmatic(
        subjectTokenProvider: StaticSubjectTokenProvider(token: idToken)
      ),
      audience: audience,
      subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
      tokenURL: URL(string: "https://sts.googleapis.com/v1/token")!
    )

    // 3. Request auth headers (triggers real STS token exchange)
    let headers = try await creds.headers()
    let authHeader = headers.first(where: { $0.0.lowercased() == "authorization" })

    #expect(authHeader != nil)
    #expect(authHeader?.1.hasPrefix("Bearer ya29.") == true)

    // 4. Also verify public Credentials API wrapper
    let config = ExternalAccountConfig(
      credentialSource: .programmatic(
        subjectTokenProvider: StaticSubjectTokenProvider(token: idToken)
      ),
      audience: audience,
      subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
      tokenURL: URL(string: "https://sts.googleapis.com/v1/token")!
    )
    let publicCredentials = try Credentials(configuration: .programmaticExternalAccount(config))
    let publicHeaders = try await publicCredentials.headers()
    let publicAuthHeader = publicHeaders.first(where: { $0.0.lowercased() == "authorization" })

    #expect(publicAuthHeader != nil)
    #expect(publicAuthHeader?.1.hasPrefix("Bearer ya29.") == true)
  }
}
