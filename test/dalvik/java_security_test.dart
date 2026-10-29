import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:green_farm_port/engine/dalvik/java_core.dart';
import 'package:green_farm_port/engine/dalvik/java_security.dart';
import 'package:green_farm_port/engine/dalvik/runtime.dart';
import 'package:green_farm_port/generated/c0085.dart';
import 'package:green_farm_port/generated/c0087.dart';

const digestClass = 'Ljava/security/MessageDigest;';
const cipherClass = 'Ljavax/crypto/Cipher;';
const secretClass = 'Ljavax/crypto/spec/SecretKeySpec;';
const ivClass = 'Ljavax/crypto/spec/IvParameterSpec;';
const keyFactory = 'Ljava/security/KeyFactory;';
const x509Class = 'Ljava/security/spec/X509EncodedKeySpec;';

void main() {
  final vectors = (jsonDecode(
    File('test/fixtures/dalvik/security_oracle.json').readAsStringSync(),
  ) as List<dynamic>).cast<Map<String, dynamic>>();
  late DalvikRuntime vm;
  setUp(() {
    vm = DalvikRuntime();
    registerJavaCore(vm);
    registerJavaSecurity(vm);
  });
  Uint8List unhex(String value) => Uint8List.fromList(
    List.generate(
      value.length ~/ 2,
      (i) => int.parse(value.substring(i * 2, i * 2 + 2), radix: 16),
    ),
  );
  String hex(List<int> value) =>
      value.map((n) => (n & 255).toRadixString(16).padLeft(2, '0')).join();
  DalvikArray array(List<int> bytes) {
    final value = vm.array('[B', bytes.length);
    for (var n = 0; n < bytes.length; n++) {
      value.values[n] = bytes[n].toSigned(8);
    }
    return value;
  }

  List<int> bytes(Object? value) =>
      vm.asArray(value).values.map((v) => (v as int) & 255).toList();
  Object? call(
    DalvikObject value,
    String owner,
    String member, [
    List<Object?> args = const [],
  ]) => vm.call('$owner->$member', [value, ...args], kind: 'virtual');
  DalvikObject make(String owner, String descriptor, List<Object?> args) {
    final value = vm.allocate(owner);
    vm.call('$owner-><init>$descriptor', [value, ...args], kind: 'direct');
    return value;
  }

  DalvikObject cipher(String name) => vm.call(
    '$cipherClass->getInstance(Ljava/lang/String;)Ljavax/crypto/Cipher;',
    [vm.intern(name)],
    kind: 'static',
  ) as DalvikObject;
  DalvikObject secret(List<int> key, String algorithm) => make(
    secretClass,
    '([BLjava/lang/String;)V',
    [array(key), vm.intern(algorithm)],
  );
  DalvikObject initialized(
    String algorithm,
    List<int> key,
    int mode, [
    List<int>? iv,
  ]) {
    final value = cipher(algorithm);
    final keyObject = secret(key, algorithm.startsWith('AES') ? 'AES' : 'DES');
    if (iv == null) {
      call(value, cipherClass, 'init(ILjava/security/Key;)V', [
        mode,
        keyObject,
      ]);
    } else {
      call(
        value,
        cipherClass,
        'init(ILjava/security/Key;Ljava/security/spec/AlgorithmParameterSpec;)V',
        [
          mode,
          keyObject,
          make(ivClass, '([B)V', [array(iv)]),
        ],
      );
    }
    return value;
  }

  List<int> finish(DalvikObject cipher, List<int> input) =>
      bytes(call(cipher, cipherClass, 'doFinal([B)[B', [array(input)]));
  Matcher javaError(String name) => throwsA(
    isA<DalvikThrown>().having(
      (e) => e.object.className,
      'Java exception',
      'L$name;',
    ),
  );
  DalvikObject publicKey(Map<String, dynamic> vector) {
    final factory = vm.call(
      '$keyFactory->getInstance(Ljava/lang/String;)Ljava/security/KeyFactory;',
      [vm.intern('RSA')],
      kind: 'static',
    ) as DalvikObject;
    return call(
      factory,
      keyFactory,
      'generatePublic(Ljava/security/spec/KeySpec;)Ljava/security/PublicKey;',
      [
        make(x509Class, '([B)V', [
          array(unhex(vector['public_x509'] as String)),
        ]),
      ],
    ) as DalvikObject;
  }

  for (var index = 0; index < vectors.length; index++) {
    final vector = vectors[index];
    if (vector['kind'] == 'digest') {
      test('JDK digest vector $index ${vector['algorithm']}', () {
        final digest = vm.call(
          '$digestClass->getInstance(Ljava/lang/String;)Ljava/security/MessageDigest;',
          [vm.intern(vector['algorithm'] as String)],
          kind: 'static',
        ) as DalvikObject;
        final actual = bytes(
          call(digest, digestClass, 'digest([B)[B', [
            array(unhex(vector['input'] as String)),
          ]),
        );
        expect(hex(actual), vector['digest']);
      });
    } else if (vector['kind'] == 'block') {
      test('JDK cipher vector $index ${vector['algorithm']}', () {
        final name = vector['algorithm'] as String,
            key = unhex(vector['key'] as String);
        final iv = (vector['iv'] as String).isEmpty
            ? null
            : unhex(vector['iv'] as String);
        final plain = unhex(vector['input'] as String),
            encrypted = unhex(vector['encrypted'] as String);
        final encryptor = initialized(name, key, 1, iv);
        expect(finish(encryptor, plain), encrypted);
        expect(
          finish(encryptor, plain),
          encrypted,
          reason: 'doFinal resets to initialized state',
        );
        expect(finish(initialized(name, key, 2, iv), encrypted), plain);
      });
    } else if (vector['kind'] == 'des_key') {
      test('JDK DES key parity and first-eight-byte semantics', () {
        final spec = make('Ljavax/crypto/spec/DESKeySpec;', '([B)V', [
          array(unhex(vector['input'] as String)),
        ]);
        final factory = vm.call(
          'Ljavax/crypto/SecretKeyFactory;->getInstance(Ljava/lang/String;)Ljavax/crypto/SecretKeyFactory;',
          [vm.intern('DES')],
          kind: 'static',
        ) as DalvikObject;
        final key = call(
          factory,
          'Ljavax/crypto/SecretKeyFactory;',
          'generateSecret(Ljava/security/spec/KeySpec;)Ljavax/crypto/SecretKey;',
          [spec],
        ) as DalvikObject;
        expect(
          hex(bytes(call(key, 'Ljavax/crypto/SecretKey;', 'getEncoded()[B'))),
          vector['encoded'],
        );
      });
    } else if (vector['kind'] == 'rsa') {
      test(
        'JDK RSA private encryption decrypts with original public-key path',
        () {
          final rsa = cipher('RSA/ECB/PKCS1Padding');
          call(rsa, cipherClass, 'init(ILjava/security/Key;)V', [
            2,
            publicKey(vector),
          ]);
          expect(
            finish(rsa, unhex(vector['encrypted_private'] as String)),
            unhex(vector['input'] as String),
          );
        },
      );
    } else if (vector['kind'] == 'original_properties') {
      test('actual generated DefReader decrypts original content.bin', () {
        registerClass85(vm);
        registerClass87(vm);
        final reader = make('Lc/c/a/b/e;', '()V', []);
        final encoded = File('assets/platform/content.bin').readAsStringSync();
        final plain = vm.string(
          call(
            reader,
            'Lc/c/a/b/e;',
            'b(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;',
            [vm.intern(encoded), vm.intern('19GmLfT99')],
          ),
        );
        expect(
          utf8.encode(plain).length,
          int.parse(vector['plaintext_length'] as String),
        );
        expect(
          crypto.sha256.convert(utf8.encode(plain)).toString(),
          vector['plaintext_sha256'],
        );
        expect(plain, contains('Green Farm 3'));
        expect(plain, contains('4.4.4'));
      });
    }
  }

  test('incremental digest, digest reset and explicit reset match Java', () {
    final digest = vm.call(
      '$digestClass->getInstance(Ljava/lang/String;)Ljava/security/MessageDigest;',
      [vm.intern('SHA-256')],
      kind: 'static',
    ) as DalvikObject;
    call(digest, digestClass, 'update([B)V', [array(utf8.encode('a'))]);
    call(digest, digestClass, 'update(B)V', [98]);
    expect(
      hex(
        bytes(
          call(digest, digestClass, 'digest([B)[B', [
            array([99]),
          ]),
        ),
      ),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
    expect(
      hex(bytes(call(digest, digestClass, 'digest()[B'))),
      crypto.sha256.convert([]).toString(),
    );
    call(digest, digestClass, 'update([B)V', [
      array([1, 2, 3]),
    ]);
    call(digest, digestClass, 'reset()V');
    expect(
      hex(bytes(call(digest, digestClass, 'digest()[B'))),
      crypto.sha256.convert([]).toString(),
    );
  });

  test(
    'PKCS7 alias and CBC auto-generated IV retain actual cipher behavior',
    () {
      final key = Uint8List.fromList(List.generate(16, (n) => n));
      final plain = utf8.encode('CBC auto-IV round trip');
      final encrypt = initialized('AES/CBC/PKCS7Padding', key, 1);
      final iv = bytes(call(encrypt, cipherClass, 'getIV()[B'));
      expect(iv.length, 16);
      final encoded = finish(encrypt, plain);
      expect(
        finish(initialized('AES/CBC/PKCS5Padding', key, 2, iv), encoded),
        plain,
      );
    },
  );

  test('all invalid padding bytes and illegal block lengths are rejected', () {
    final key = Uint8List(16);
    for (final suffix in [
      [0],
      [17],
      [3, 2],
    ]) {
      final padded = Uint8List(16)..setRange(16 - suffix.length, 16, suffix);
      final invalid = finish(initialized('AES/ECB/NoPadding', key, 1), padded);
      expect(
        () => finish(initialized('AES', key, 2), invalid),
        javaError('javax/crypto/BadPaddingException'),
      );
    }
    expect(
      () => finish(initialized('AES/ECB/NoPadding', key, 1), [1]),
      javaError('javax/crypto/IllegalBlockSizeException'),
    );
    expect(
      () => finish(initialized('AES', key, 2), [1]),
      javaError('javax/crypto/IllegalBlockSizeException'),
    );
  });

  test(
    'invalid keys, algorithms, IVs and uninitialized ciphers fail explicitly',
    () {
      expect(
        () => cipher('invented'),
        javaError('java/security/NoSuchAlgorithmException'),
      );
      expect(
        () => cipher('AES/ECB/InventedPadding'),
        javaError('javax/crypto/NoSuchPaddingException'),
      );
      expect(
        () => initialized('AES', [1, 2, 3], 1),
        javaError('java/security/InvalidKeyException'),
      );
      expect(
        () => initialized('AES/CBC/PKCS5Padding', Uint8List(16), 2),
        javaError('java/security/InvalidKeyException'),
      );
      expect(
        () => initialized('AES/CBC/PKCS5Padding', Uint8List(16), 1, [1]),
        javaError('java/security/InvalidAlgorithmParameterException'),
      );
      expect(
        () => finish(cipher('AES'), [1]),
        javaError('java/lang/IllegalStateException'),
      );
      expect(
        () => secret([], 'AES'),
        javaError('java/lang/IllegalArgumentException'),
      );
    },
  );

  test('secret keys, IVs and encoded keys copy input and output arrays', () {
    final keyBytes = array(List.filled(16, 9));
    final key = make(secretClass, '([BLjava/lang/String;)V', [
      keyBytes,
      vm.intern('AES'),
    ]);
    keyBytes.values[0] = 0;
    expect(bytes(call(key, secretClass, 'getEncoded()[B')), List.filled(16, 9));
    final output = call(key, secretClass, 'getEncoded()[B') as DalvikArray;
    output.values[0] = 0;
    expect(bytes(call(key, secretClass, 'getEncoded()[B')).first, 9);
    final ivInput = array([1, 2, 3, 4]);
    final iv = make(ivClass, '([BII)V', [ivInput, 1, 2]);
    ivInput.values[1] = 9;
    expect(bytes(call(iv, ivClass, 'getIV()[B')), [2, 3]);
  });

  test('RSA public encryption has valid nonzero PKCS1 padding and decrypts mathematically', () {
    final vector = vectors.singleWhere((v) => v['kind'] == 'rsa');
    final rsa = cipher('RSA/ECB/PKCS1Padding');
    call(rsa, cipherClass, 'init(ILjava/security/Key;)V', [
      1,
      publicKey(vector),
    ]);
    final plain = unhex(vector['input'] as String),
        encrypted = finish(rsa, plain);
    final modulus = BigInt.parse(vector['modulus'] as String, radix: 16);
    final exponent = BigInt.parse(
      vector['private_exponent'] as String,
      radix: 16,
    );
    final raw = BigInt.parse(
      hex(encrypted),
      radix: 16,
    ).modPow(exponent, modulus);
    final block = unhex(
      raw.toRadixString(16).padLeft(encrypted.length * 2, '0'),
    );
    expect(block.sublist(0, 2), [0, 2]);
    final delimiter = block.indexOf(0, 2);
    expect(delimiter, greaterThanOrEqualTo(10));
    expect(block.sublist(delimiter + 1), plain);
  });

  test(
    'malformed RSA DER and padding fail with actual Java exception types',
    () {
      final vector = vectors.singleWhere((v) => v['kind'] == 'rsa');
      final bad = Map<String, dynamic>.from(vector)
        ..['public_x509'] = '3003020101';
      expect(
        () => publicKey(bad),
        javaError('java/security/spec/InvalidKeySpecException'),
      );
      final rsa = cipher('RSA/ECB/PKCS1Padding');
      call(rsa, cipherClass, 'init(ILjava/security/Key;)V', [
        2,
        publicKey(vector),
      ]);
      expect(
        () => finish(rsa, Uint8List(256)),
        javaError('javax/crypto/BadPaddingException'),
      );
      expect(
        () => finish(rsa, Uint8List(257)),
        javaError('javax/crypto/IllegalBlockSizeException'),
      );
    },
  );

  test('SecureRandom uses a real host entropy source and enforces bounds', () {
    final random = make('Ljava/security/SecureRandom;', '()V', []);
    final result = vm.array('[B', 64);
    call(random, 'Ljava/security/SecureRandom;', 'nextBytes([B)V', [result]);
    expect(
      result.values.every((n) => n is int && n >= -128 && n <= 127),
      isTrue,
    );
    expect(call(random, 'Ljava/security/SecureRandom;', 'nextInt(I)I', [1]), 0);
    expect(
      () => call(random, 'Ljava/security/SecureRandom;', 'nextInt(I)I', [0]),
      javaError('java/lang/IllegalArgumentException'),
    );
  });
}
