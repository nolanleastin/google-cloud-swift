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

// PROOF OF CONCEPT, hand-written stand-in for what sidekick would emit.
//
// Converting an `Any` through SwiftProtobuf's JSON transcoder requires the
// payload type to be in SwiftProtobuf's process-global type registry, which
// nothing in this SDK populates. Long running operations carry a closed set of
// payload types that the service declares up front, so the generator can emit a
// table that maps each type URL to a conversion that never consults the
// registry.

import Foundation
import GoogleCloudGax
internal import StorageControlProtos
internal import SwiftProtobuf
@_spi(GoogleCloudInternal) import GoogleCloudWKT

internal enum StorageControlLROAny {
  // Converts the `Any` carried by an operation's metadata or response into its
  // native representation, dispatching on the type URL.
  internal static func fromProto(
    _ proto: SwiftProtobuf.Google_Protobuf_Any
  ) throws -> GoogleCloudWKT.`Any` {
    switch proto.typeURL {
    case RenameFolderMetadata._anyTypeUrl:
      return try .init(
        fromMessage: RenameFolderMetadata(
          proto: RenameFolderMetadata.ProtoType(serializedBytes: proto.value)))
    case Folder._anyTypeUrl:
      return try .init(
        fromMessage: Folder(proto: Folder.ProtoType(serializedBytes: proto.value)))
    default:
      throw ProtobufConversionError.unknownTypeUrl(typeUrl: proto.typeURL)
    }
  }

  // Converts a native `Any` back to its protobuf representation, dispatching on
  // the type URL.
  internal static func toProto(
    _ any: GoogleCloudWKT.`Any`
  ) throws -> SwiftProtobuf.Google_Protobuf_Any {
    switch any.typeUrl {
    case RenameFolderMetadata._anyTypeUrl:
      return try .init(message: RenameFolderMetadata(fromAny: any).toProto())
    case Folder._anyTypeUrl:
      return try .init(message: Folder(fromAny: any).toProto())
    default:
      throw ProtobufConversionError.unknownTypeUrl(typeUrl: any.typeUrl)
    }
  }
}
