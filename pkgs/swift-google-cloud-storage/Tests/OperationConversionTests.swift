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

import GoogleCloudWKT
import GoogleLongRunning
import StorageControlProtos
import Testing

@testable import GoogleCloudStorage

@Suite struct OperationConversionTests {
  // Builds the `Operation` the service returns for a completed `renameFolder()`.
  private func renameFolderOperation() throws
    -> StorageControlProtos.Google_Longrunning_Operation
  {
    var metadata = StorageControlProtos.Google_Storage_Control_V2_RenameFolderMetadata()
    metadata.sourceFolderID = "example-folder-id/"
    metadata.destinationFolderID = "renamed-folder-id/"

    var folder = StorageControlProtos.Google_Storage_Control_V2_Folder()
    folder.name = "projects/_/buckets/test-bucket/folders/renamed-folder-id/"
    folder.metageneration = 1

    var operation = StorageControlProtos.Google_Longrunning_Operation()
    operation.name = "projects/_/buckets/test-bucket/operations/test-operation"
    operation.metadata = try .init(message: metadata)
    operation.done = true
    operation.response = try .init(message: folder)
    return operation
  }

  // An `Any` built in this process holds its payload as a message, and can be
  // serialized to JSON without consulting the SwiftProtobuf type registry.
  @Test func operationConvertsWhenAnyHoldsAMessage() throws {
    let operation = try renameFolderOperation()

    let native = try GoogleLongRunning.Operation(proto: operation)

    #expect(native.name == operation.name)
    let metadata = try RenameFolderMetadata(fromAny: #require(native.metadata))
    #expect(metadata.destinationFolderId == "renamed-folder-id/")
  }

  // An `Any` parsed from the wire holds its payload as bytes. Converting it
  // requires looking the payload type up in the SwiftProtobuf type registry.
  @Test func operationConvertsWhenAnyArrivesFromTheWire() throws {
    let sent = try renameFolderOperation()
    let bytes: [UInt8] = try sent.serializedBytes()
    let received = try StorageControlProtos.Google_Longrunning_Operation(serializedBytes: bytes)

    let native = try GoogleLongRunning.Operation(proto: received)

    #expect(native.name == sent.name)
    let metadata = try RenameFolderMetadata(fromAny: #require(native.metadata))
    #expect(metadata.destinationFolderId == "renamed-folder-id/")
  }

  // A payload that serializes to zero bytes never reaches the type registry
  // lookup, so an operation carrying one converts even though it arrives from
  // the wire with the same type URL as the case above.
  @Test func operationConvertsWhenAnyPayloadIsEmpty() throws {
    var sent = StorageControlProtos.Google_Longrunning_Operation()
    sent.name = "projects/_/buckets/test-bucket/operations/test-operation"
    sent.metadata = try .init(
      message: StorageControlProtos.Google_Storage_Control_V2_RenameFolderMetadata())
    sent.done = true

    let bytes: [UInt8] = try sent.serializedBytes()
    let received = try StorageControlProtos.Google_Longrunning_Operation(serializedBytes: bytes)

    let native = try GoogleLongRunning.Operation(proto: received)

    #expect(native.name == sent.name)
    let metadata = try RenameFolderMetadata(fromAny: #require(native.metadata))
    #expect(metadata.destinationFolderId == "")
  }
}
