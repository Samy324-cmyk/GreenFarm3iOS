import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart' as pc;

import 'numbers.dart';
import 'runtime.dart';

const _digest = 'Ljava/security/MessageDigest;';
const _cipher = 'Ljavax/crypto/Cipher;';
const _secret = 'Ljavax/crypto/spec/SecretKeySpec;';
const _iv = 'Ljavax/crypto/spec/IvParameterSpec;';
const _des = 'Ljavax/crypto/spec/DESKeySpec;';
const _secretFactory = 'Ljavax/crypto/SecretKeyFactory;';
const _keyFactory = 'Ljava/security/KeyFactory;';
const _x509 = 'Ljava/security/spec/X509EncodedKeySpec;';
const _publicKey = 'Lport/RsaPublicKey;';
const _secureRandom = 'Ljava/security/SecureRandom;';

Uint8List _bytes(DalvikRuntime vm, Object? value) {
  final array = vm.asArray(value);
  if (array.className != '[B') throw StateError('Expected Java byte[]');
  return Uint8List.fromList(array.values.map((v) => (v as int) & 255).toList());
}

DalvikArray _array(DalvikRuntime vm, List<int> bytes) {
  final result = vm.array('[B', bytes.length);
  for (var n = 0; n < bytes.length; n++) {
    result.values[n] = bytes[n].toSigned(8);
  }
  return result;
}

class _Digest {
  _Digest(this.algorithm, this.hash);
  final String algorithm;
  final crypto.Hash hash;
  final List<int> bytes = [];
}

class _SecretKey {
  _SecretKey(this.bytes, this.algorithm);
  final Uint8List bytes;
  final String algorithm;
}

class _PublicKey {
  _PublicKey(this.key, this.encoded);
  final pc.RSAPublicKey key;
  final Uint8List encoded;
}

/// Strict DER reader for the RSA SubjectPublicKeyInfo form used by the game.
class _Der {
  _Der(this.bytes);
  final Uint8List bytes;
  int offset = 0;
  bool get done => offset == bytes.length;
  Uint8List read(int tag) {
    if (offset >= bytes.length ||
        bytes[offset++] != tag ||
        offset >= bytes.length) {
      throw const FormatException('Invalid DER tag');
    }
    var length = bytes[offset++];
    if (length & 0x80 != 0) {
      final count = length & 0x7f;
      if (count == 0 ||
          count > 4 ||
          offset + count > bytes.length ||
          bytes[offset] == 0) {
        throw const FormatException('Invalid DER length');
      }
      length = 0;
      for (var n = 0; n < count; n++) {
        length = (length << 8) | bytes[offset++];
      }
      if (length < 128) throw const FormatException('Noncanonical DER length');
    }
    if (length > bytes.length - offset) {
      throw const FormatException('Truncated DER');
    }
    final value = Uint8List.sublistView(bytes, offset, offset + length);
    offset += length;
    return value;
  }

  BigInt integer() {
    final value = read(2);
    if (value.isEmpty ||
        value[0] & 0x80 != 0 ||
        (value.length > 1 && value[0] == 0 && value[1] & 0x80 == 0)) {
      throw const FormatException('Invalid positive DER integer');
    }
    var result = BigInt.zero;
    for (final byte in value) {
      result = (result << 8) | BigInt.from(byte);
    }
    if (result <= BigInt.zero) {
      throw const FormatException('Nonpositive RSA parameter');
    }
    return result;
  }
}

_PublicKey _rsaPublic(Uint8List encoded) {
  final outer = _Der(encoded);
  final subject = _Der(outer.read(0x30));
  if (!outer.done) throw const FormatException('Trailing public key bytes');
  final algorithm = _Der(subject.read(0x30));
  final oid = algorithm.read(6);
  const rsaOid = [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 1, 1, 1];
  if (oid.length != rsaOid.length ||
      List.generate(oid.length, (i) => oid[i] == rsaOid[i]).contains(false)) {
    throw const FormatException('Public key is not RSA');
  }
  if (!algorithm.done && algorithm.read(5).isNotEmpty) {
    throw const FormatException('Invalid RSA parameters');
  }
  if (!algorithm.done) {
    throw const FormatException('Trailing RSA algorithm data');
  }
  final bits = subject.read(3);
  if (!subject.done || bits.isEmpty || bits[0] != 0) {
    throw const FormatException('Invalid public key bit string');
  }
  final wrapper = _Der(Uint8List.sublistView(bits, 1));
  final rsa = _Der(wrapper.read(0x30));
  final modulus = rsa.integer(), exponent = rsa.integer();
  if (!wrapper.done ||
      !rsa.done ||
      modulus.isEven ||
      exponent.isEven ||
      exponent < BigInt.from(3)) {
    throw const FormatException('Invalid RSA public parameters');
  }
  return _PublicKey(
    pc.RSAPublicKey(modulus, exponent),
    Uint8List.fromList(encoded),
  );
}

Uint8List _entropy(int count) {
  final random = math.Random.secure();
  return Uint8List.fromList(List.generate(count, (_) => random.nextInt(256)));
}

class _Cipher {
  _Cipher(this.transformation, this.algorithm, this.mode, this.padding);
  final String transformation, algorithm, mode, padding;
  Object? key;
  Uint8List? iv;
  int? operation;
  int get blockSize => algorithm == 'AES'
      ? 16
      : algorithm == 'DES'
      ? 8
      : 0;
  bool get padded => padding != 'NOPADDING';

  Uint8List finish(DalvikRuntime vm, Uint8List input) {
    if (operation == null) {
      vm.throwJava(
        'Ljava/lang/IllegalStateException;',
        'Cipher not initialized',
      );
    }
    final encrypt = operation == 1;
    if (algorithm == 'RSA') {
      final public = key as _PublicKey;
      final keyBytes = (public.key.modulus!.bitLength + 7) ~/ 8;
      if (input.length > keyBytes - (encrypt ? 11 : 0)) {
        vm.throwJava(
          'Ljavax/crypto/IllegalBlockSizeException;',
          'RSA input too large',
        );
      }
      final random = pc.FortunaRandom()..seed(pc.KeyParameter(_entropy(32)));
      final rsa = pc.PKCS1Encoding(pc.RSAEngine())
        ..init(
          encrypt,
          pc.ParametersWithRandom(
            pc.PublicKeyParameter<pc.RSAPublicKey>(public.key),
            random,
          ),
        );
      try {
        return rsa.process(input);
      } on ArgumentError catch (error) {
        vm.throwJava('Ljavax/crypto/BadPaddingException;', error.toString());
      }
    }
    final secret = key as _SecretKey;
    if ((!encrypt || !padded) && input.length % blockSize != 0) {
      vm.throwJava(
        'Ljavax/crypto/IllegalBlockSizeException;',
        'Input is not a whole number of blocks',
      );
    }
    Uint8List bytes;
    if (encrypt && padded) {
      final pad = blockSize - input.length % blockSize;
      bytes = Uint8List(input.length + pad)..setRange(0, input.length, input);
      bytes.fillRange(input.length, bytes.length, pad);
    } else {
      bytes = input;
    }
    // DES-EDE with K1=K2=K3 is exactly single DES: E(K,D(K,E(K,x))).
    final pc.BlockCipher engine = algorithm == 'AES'
        ? pc.AESEngine()
        : pc.DESedeEngine();
    final keyBytes = algorithm == 'AES'
        ? secret.bytes
        : Uint8List.fromList([
            ...secret.bytes,
            ...secret.bytes,
            ...secret.bytes,
          ]);
    final pc.BlockCipher blocks = mode == 'CBC'
        ? pc.CBCBlockCipher(engine)
        : pc.ECBBlockCipher(engine);
    final parameters = mode == 'CBC'
        ? pc.ParametersWithIV(pc.KeyParameter(keyBytes), iv!)
        : pc.KeyParameter(keyBytes);
    blocks.init(encrypt, parameters);
    final output = Uint8List(bytes.length);
    for (var offset = 0; offset < bytes.length; offset += blockSize) {
      blocks.processBlock(bytes, offset, output, offset);
    }
    if (!encrypt && padded) {
      if (output.isEmpty) {
        vm.throwJava(
          'Ljavax/crypto/BadPaddingException;',
          'Missing padded block',
        );
      }
      final pad = output.last;
      if (pad == 0 || pad > blockSize || pad > output.length) {
        vm.throwJava(
          'Ljavax/crypto/BadPaddingException;',
          'Invalid padding length',
        );
      }
      var mismatch = 0;
      for (var n = output.length - pad; n < output.length; n++) {
        mismatch |= output[n] ^ pad;
      }
      if (mismatch != 0) {
        vm.throwJava(
          'Ljavax/crypto/BadPaddingException;',
          'Invalid padding bytes',
        );
      }
      return Uint8List.sublistView(output, 0, output.length - pad);
    }
    return output;
  }
}

void registerJavaSecurity(DalvikRuntime vm) {
  for (final name in [
    'Key',
    'PublicKey',
    'spec/KeySpec',
    'spec/AlgorithmParameterSpec',
  ]) {
    vm.registerExternalClass('Ljava/security/$name;');
  }
  vm.registerExternalClass(
    'Ljavax/crypto/SecretKey;',
    interfaces: ['Ljava/security/Key;'],
  );
  vm.registerExternalClass(_digest);
  vm.registerExternalClass(_cipher);
  vm.registerExternalClass(
    _secret,
    interfaces: ['Ljavax/crypto/SecretKey;', 'Ljava/security/spec/KeySpec;'],
  );
  vm.registerExternalClass(
    _iv,
    interfaces: ['Ljava/security/spec/AlgorithmParameterSpec;'],
  );
  vm.registerExternalClass(_des, interfaces: ['Ljava/security/spec/KeySpec;']);
  vm.registerExternalClass(_secretFactory);
  vm.registerExternalClass(_keyFactory);
  vm.registerExternalClass(_x509, interfaces: ['Ljava/security/spec/KeySpec;']);
  vm.registerExternalClass(
    _publicKey,
    interfaces: ['Ljava/security/PublicKey;', 'Ljava/security/Key;'],
  );
  vm.registerExternalClass(_secureRandom, superclass: 'Ljava/util/Random;');
  vm.registerExternalClass(
    'Ljava/security/GeneralSecurityException;',
    superclass: 'Ljava/lang/Exception;',
  );
  for (final name in [
    'NoSuchAlgorithmException',
    'InvalidKeyException',
    'InvalidAlgorithmParameterException',
    'KeyManagementException',
    'spec/InvalidKeySpecException',
  ]) {
    vm.registerExternalClass(
      'Ljava/security/$name;',
      superclass: 'Ljava/security/GeneralSecurityException;',
    );
  }
  vm.registerExternalClass(
    'Ljava/security/InvalidParameterException;',
    superclass: 'Ljava/lang/IllegalArgumentException;',
  );
  for (final name in [
    'NoSuchPaddingException',
    'BadPaddingException',
    'IllegalBlockSizeException',
  ]) {
    vm.registerExternalClass(
      'Ljavax/crypto/$name;',
      superclass: 'Ljava/security/GeneralSecurityException;',
    );
  }
  void native(String owner, String signature, DalvikBody body) =>
      vm.registerNative('$owner->$signature', body);
  _Digest digest(Object? value) => vm.object(value).nativeValue as _Digest;
  _Cipher cipher(Object? value) => vm.object(value).nativeValue as _Cipher;
  native(
    _digest,
    'getInstance(Ljava/lang/String;)Ljava/security/MessageDigest;',
    (v, a) {
      final name = v.string(a[0]);
      final crypto.Hash hash;
      switch (name.toUpperCase().replaceAll('-', '')) {
        case 'MD5':
          hash = crypto.md5;
        case 'SHA':
        case 'SHA1':
          hash = crypto.sha1;
        case 'SHA256':
          hash = crypto.sha256;
        default:
          v.throwJava('Ljava/security/NoSuchAlgorithmException;', name);
      }
      return DalvikObject(_digest, nativeValue: _Digest(name, hash));
    },
  );
  native(_digest, 'update([B)V', (v, a) {
    digest(a[0]).bytes.addAll(_bytes(v, a[1]));
    return null;
  });
  native(_digest, 'update(B)V', (v, a) {
    digest(a[0]).bytes.add(JBits.int32(a[1]) & 255);
    return null;
  });
  native(_digest, 'update([BII)V', (v, a) {
    final bytes = _bytes(v, a[1]),
        offset = JBits.int32(a[2]),
        length = JBits.int32(a[3]);
    if (offset < 0 || length < 0 || offset > bytes.length - length) {
      v.throwJava(
        'Ljava/lang/IllegalArgumentException;',
        'Invalid input range',
      );
    }
    digest(a[0]).bytes.addAll(bytes.sublist(offset, offset + length));
    return null;
  });
  for (final withInput in [false, true]) {
    native(_digest, 'digest(${withInput ? '[B' : ''})[B', (v, a) {
      final state = digest(a[0]);
      if (withInput) state.bytes.addAll(_bytes(v, a[1]));
      final value = state.hash.convert(state.bytes).bytes;
      state.bytes.clear();
      return _array(v, value);
    });
  }
  native(_digest, 'reset()V', (v, a) {
    digest(a[0]).bytes.clear();
    return null;
  });
  native(
    _digest,
    'getAlgorithm()Ljava/lang/String;',
    (v, a) => v.intern(digest(a[0]).algorithm),
  );
  native(
    _digest,
    'getDigestLength()I',
    (v, a) => digest(a[0]).hash.convert([]).bytes.length,
  );
  native(_secret, '<init>([BLjava/lang/String;)V', (v, a) {
    if (v.isNull(a[1]) || v.isNull(a[2])) {
      v.throwJava('Ljava/lang/IllegalArgumentException;', 'Missing argument');
    }
    final bytes = _bytes(v, a[1]);
    if (bytes.isEmpty) {
      v.throwJava('Ljava/lang/IllegalArgumentException;', 'Empty key');
    }
    v.object(a[0]).nativeValue = _SecretKey(bytes, v.string(a[2]));
    return null;
  });
  native(
    _secret,
    'getEncoded()[B',
    (v, a) => _array(v, (v.object(a[0]).nativeValue as _SecretKey).bytes),
  );
  native(
    _secret,
    'getAlgorithm()Ljava/lang/String;',
    (v, a) => v.intern((v.object(a[0]).nativeValue as _SecretKey).algorithm),
  );
  native(_secret, 'getFormat()Ljava/lang/String;', (v, a) => v.intern('RAW'));
  for (final ranged in [false, true]) {
    native(_iv, '<init>([B${ranged ? 'II' : ''})V', (v, a) {
      final bytes = _bytes(v, a[1]);
      final offset = ranged ? JBits.int32(a[2]) : 0,
          length = ranged ? JBits.int32(a[3]) : bytes.length;
      if (offset < 0 || length < 0 || offset > bytes.length - length) {
        v.throwJava('Ljava/lang/ArrayIndexOutOfBoundsException;');
      }
      v.object(a[0]).nativeValue = Uint8List.fromList(
        bytes.sublist(offset, offset + length),
      );
      return null;
    });
  }
  native(
    _iv,
    'getIV()[B',
    (v, a) => _array(v, v.object(a[0]).nativeValue as Uint8List),
  );
  native(_des, '<init>([B)V', (v, a) {
    final bytes = _bytes(v, a[1]);
    if (bytes.length < 8) {
      v.throwJava('Ljava/security/InvalidKeyException;', 'Wrong key size');
    }
    v.object(a[0]).nativeValue = Uint8List.fromList(bytes.sublist(0, 8));
    return null;
  });
  native(
    _des,
    'getKey()[B',
    (v, a) => _array(v, v.object(a[0]).nativeValue as Uint8List),
  );
  native(
    _secretFactory,
    'getInstance(Ljava/lang/String;)Ljavax/crypto/SecretKeyFactory;',
    (v, a) {
      final name = v.string(a[0]);
      if (name.toUpperCase() != 'DES') {
        v.throwJava('Ljava/security/NoSuchAlgorithmException;', name);
      }
      return DalvikObject(_secretFactory, nativeValue: name);
    },
  );
  native(
    _secretFactory,
    'generateSecret(Ljava/security/spec/KeySpec;)Ljavax/crypto/SecretKey;',
    (v, a) {
      final spec = v.object(a[1]);
      if (spec.className != _des) {
        v.throwJava(
          'Ljava/security/spec/InvalidKeySpecException;',
          'Expected DESKeySpec',
        );
      }
      final key = Uint8List.fromList(spec.nativeValue as Uint8List);
      for (var n = 0; n < key.length; n++) {
        var bits = key[n] & 0xfe, parity = 1;
        for (var bit = 1; bit < 8; bit++) {
          parity ^= (bits >> bit) & 1;
        }
        key[n] = bits | parity;
      }
      return DalvikObject(_secret, nativeValue: _SecretKey(key, 'DES'));
    },
  );
  native(_x509, '<init>([B)V', (v, a) {
    v.object(a[0]).nativeValue = _bytes(v, a[1]);
    return null;
  });
  native(
    _x509,
    'getEncoded()[B',
    (v, a) => _array(v, v.object(a[0]).nativeValue as Uint8List),
  );
  native(
    _keyFactory,
    'getInstance(Ljava/lang/String;)Ljava/security/KeyFactory;',
    (v, a) {
      final name = v.string(a[0]);
      if (name.toUpperCase() != 'RSA') {
        v.throwJava('Ljava/security/NoSuchAlgorithmException;', name);
      }
      return DalvikObject(_keyFactory, nativeValue: name);
    },
  );
  native(
    _keyFactory,
    'generatePublic(Ljava/security/spec/KeySpec;)Ljava/security/PublicKey;',
    (v, a) {
      final spec = v.object(a[1]);
      if (spec.className != _x509) {
        v.throwJava(
          'Ljava/security/spec/InvalidKeySpecException;',
          'Expected X509EncodedKeySpec',
        );
      }
      try {
        return DalvikObject(
          _publicKey,
          nativeValue: _rsaPublic(spec.nativeValue as Uint8List),
        );
      } on FormatException catch (error) {
        v.throwJava(
          'Ljava/security/spec/InvalidKeySpecException;',
          error.message,
        );
      }
    },
  );
  native(
    _publicKey,
    'getEncoded()[B',
    (v, a) => _array(v, (v.object(a[0]).nativeValue as _PublicKey).encoded),
  );
  native(
    _publicKey,
    'getAlgorithm()Ljava/lang/String;',
    (v, a) => v.intern('RSA'),
  );
  native(
    _publicKey,
    'getFormat()Ljava/lang/String;',
    (v, a) => v.intern('X.509'),
  );
  native(_cipher, 'getInstance(Ljava/lang/String;)Ljavax/crypto/Cipher;', (
    v,
    a,
  ) {
    final name = v.string(a[0]),
        parts = v.string(a[0]).toUpperCase().split('/');
    if (parts.length != 1 && parts.length != 3) {
      v.throwJava('Ljava/security/NoSuchAlgorithmException;', name);
    }
    final algorithm = parts[0];
    final mode = parts.length == 3 ? parts[1] : 'ECB';
    final padding = parts.length == 3
        ? parts[2]
        : algorithm == 'RSA'
        ? 'PKCS1PADDING'
        : 'PKCS5PADDING';
    if (!['AES', 'DES', 'RSA'].contains(algorithm) ||
        !['ECB', 'CBC'].contains(mode) ||
        (algorithm == 'RSA' && mode != 'ECB')) {
      v.throwJava('Ljava/security/NoSuchAlgorithmException;', name);
    }
    if (!(algorithm == 'RSA'
            ? ['PKCS1PADDING']
            : ['PKCS5PADDING', 'PKCS7PADDING', 'NOPADDING'])
        .contains(padding)) {
      v.throwJava('Ljavax/crypto/NoSuchPaddingException;', padding);
    }
    return DalvikObject(
      _cipher,
      nativeValue: _Cipher(name, algorithm, mode, padding),
    );
  });
  for (final withParameters in [false, true]) {
    native(
      _cipher,
      'init(ILjava/security/Key;${withParameters ? 'Ljava/security/spec/AlgorithmParameterSpec;' : ''})V',
      (v, a) {
        final state = cipher(a[0]);
        state.operation = null;
        final operation = JBits.int32(a[1]);
        if (operation != 1 && operation != 2) {
          v.throwJava(
            'Ljava/security/InvalidParameterException;',
            'Unsupported cipher mode',
          );
        }
        if (v.isNull(a[2])) {
          v.throwJava('Ljava/security/InvalidKeyException;', 'No key');
        }
        final key = v.object(a[2]).nativeValue;
        if (state.algorithm == 'RSA') {
          if (key is! _PublicKey) {
            v.throwJava(
              'Ljava/security/InvalidKeyException;',
              'Expected RSA public key',
            );
          }
        } else {
          if (key is! _SecretKey ||
              key.algorithm.toUpperCase() != state.algorithm ||
              !(state.algorithm == 'AES' ? [16, 24, 32] : [8]).contains(
                key.bytes.length,
              )) {
            v.throwJava(
              'Ljava/security/InvalidKeyException;',
              'Wrong algorithm or key length',
            );
          }
        }
        Uint8List? iv;
        if (withParameters && !v.isNull(a[3])) {
          final spec = v.object(a[3]);
          if (spec.className != _iv || state.mode != 'CBC') {
            v.throwJava(
              'Ljava/security/InvalidAlgorithmParameterException;',
              'Unexpected cipher parameters',
            );
          }
          iv = Uint8List.fromList(spec.nativeValue as Uint8List);
          if (iv.length != state.blockSize) {
            v.throwJava(
              'Ljava/security/InvalidAlgorithmParameterException;',
              'Wrong IV length',
            );
          }
        }
        if (state.mode == 'CBC' && iv == null) {
          if (operation == 2) {
            v.throwJava(
              withParameters
                  ? 'Ljava/security/InvalidAlgorithmParameterException;'
                  : 'Ljava/security/InvalidKeyException;',
              'Missing IV',
            );
          }
          iv = _entropy(state.blockSize);
        }
        state.key = key;
        state.iv = iv;
        state.operation = operation;
        return null;
      },
    );
  }
  native(
    _cipher,
    'doFinal([B)[B',
    (v, a) => _array(v, cipher(a[0]).finish(v, _bytes(v, a[1]))),
  );
  native(
    _cipher,
    'getIV()[B',
    (v, a) => cipher(a[0]).iv == null ? null : _array(v, cipher(a[0]).iv!),
  );
  native(_cipher, 'getBlockSize()I', (v, a) => cipher(a[0]).blockSize);
  native(
    _cipher,
    'getAlgorithm()Ljava/lang/String;',
    (v, a) => v.intern(cipher(a[0]).transformation),
  );
  native(_secureRandom, '<init>()V', (v, a) {
    v.object(a[0]).nativeValue = math.Random.secure();
    return null;
  });
  native(_secureRandom, 'nextBytes([B)V', (v, a) {
    final random = v.object(a[0]).nativeValue as math.Random,
        bytes = v.asArray(a[1]);
    for (var n = 0; n < bytes.values.length; n++) {
      bytes.values[n] = random.nextInt(256).toSigned(8);
    }
    return null;
  });
  native(
    _secureRandom,
    'nextInt()I',
    (v, a) => (v.object(a[0]).nativeValue as math.Random)
        .nextInt(0x100000000)
        .toSigned(32),
  );
  native(_secureRandom, 'nextInt(I)I', (v, a) {
    final bound = JBits.int32(a[1]);
    if (bound <= 0) {
      v.throwJava(
        'Ljava/lang/IllegalArgumentException;',
        'bound must be positive',
      );
    }
    return (v.object(a[0]).nativeValue as math.Random).nextInt(bound);
  });
}
