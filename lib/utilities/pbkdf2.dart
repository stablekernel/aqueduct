part of aqueduct;

/*
  Based on implementation found here: https://github.com/jamesots/pbkdf2, which contains the following license:
  Copyright 2014 James Ots

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

      http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
 */

/// Instances of this type perform one-way cryptographic hashing using the PBKDF2 algorithm.
class PBKDF2 {
  Hash hashAlgorithm;
  List<int> blockList = new List<int>(4);

  /// Creates instance capable of generating hash.
  ///
  /// [hashAlgorithm] defaults to [sha256].
  PBKDF2({this.hashAlgorithm}) {
    hashAlgorithm ??= sha256;
  }

  /// Hashes a password with a given salt.
  List<int> generateKey(String password, String salt, int rounds, int length) {
    var blockSize = hashAlgorithm.convert([1, 2, 3]).bytes.length;
    if (length > (pow(2, 32) - 1) * blockSize) {
      throw new PBKDF2Exception("Derived key too long");
    }

    var numberOfBlocks = (length / blockSize).ceil();
    var sizeOfLastBlock = length - (numberOfBlocks - 1) * blockSize;

    var key = <int>[];
    for (var i = 1; i <= numberOfBlocks; i++) {
      var block = _computeBlock(password, salt, rounds, i);
      if (i < numberOfBlocks) {
        key.addAll(block);
      } else {
        key.addAll(block.sublist(0, sizeOfLastBlock));
      }
    }
    return key;
  }

  List<int> _computeBlock(
      String password, String salt, int iterations, int blockNumber) {
    var input = <int>[];
    input.addAll(salt.codeUnits);
    _writeBlockNumber(input, blockNumber);

    var hmac = new Hmac(hashAlgorithm, password.codeUnits);
    var lastDigest = hmac.convert(input);

    var result = lastDigest.bytes;
    for (var i = 1; i < iterations; i++) {
      hmac = new Hmac(hashAlgorithm, password.codeUnits);
      var newDigest = hmac.convert(lastDigest.bytes);
      _xorLists(result, newDigest.bytes);
      lastDigest = newDigest;
    }
    return result;
  }

  _writeBlockNumber(List<int> input, int blockNumber) {
    blockList[0] = blockNumber >> 24;
    blockList[1] = blockNumber >> 16;
    blockList[2] = blockNumber >> 8;
    blockList[3] = blockNumber;
    input.addAll(blockList);
  }

  _xorLists(List<int> list1, List<int> list2) {
    for (var i = 0; i < list1.length; i++) {
      list1[i] = list1[i] ^ list2[i];
    }
  }
}

class PBKDF2Exception {
  PBKDF2Exception(this.message);
  String message;
}
