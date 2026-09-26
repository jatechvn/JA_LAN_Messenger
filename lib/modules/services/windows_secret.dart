import 'dart:ffi';
import 'dart:typed_data';

final class _Blob extends Struct {
  @Uint32()
  external int length;
  external Pointer<Uint8> data;
}

/// Current-user DPAPI. No application key or environment-derived secret.
class WindowsSecret {
  static final _kernel = DynamicLibrary.open('kernel32.dll');
  static final _crypt = DynamicLibrary.open('crypt32.dll');
  static final _heap = _kernel
      .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
        'GetProcessHeap',
      )();
  static final _alloc = _kernel
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Uint32, IntPtr),
        Pointer<Void> Function(Pointer<Void>, int, int)
      >('HeapAlloc');
  static final _free = _kernel
      .lookupFunction<
        Int32 Function(Pointer<Void>, Uint32, Pointer<Void>),
        int Function(Pointer<Void>, int, Pointer<Void>)
      >('HeapFree');
  static final _localFree = _kernel
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>)
      >('LocalFree');

  static Uint8List transform(Uint8List bytes, {required bool protect}) {
    final input = _alloc(_heap, 8, sizeOf<_Blob>()).cast<_Blob>();
    final output = _alloc(_heap, 8, sizeOf<_Blob>()).cast<_Blob>();
    final data = _alloc(_heap, 8, bytes.length).cast<Uint8>();
    try {
      if (input == nullptr || output == nullptr || data == nullptr) {
        throw StateError('Cannot allocate credential buffer');
      }
      data.asTypedList(bytes.length).setAll(0, bytes);
      input.ref
        ..length = bytes.length
        ..data = data;
      final call = _crypt
          .lookupFunction<
            Int32 Function(
              Pointer<_Blob>,
              Pointer<Void>,
              Pointer<Void>,
              Pointer<Void>,
              Pointer<Void>,
              Uint32,
              Pointer<_Blob>,
            ),
            int Function(
              Pointer<_Blob>,
              Pointer<Void>,
              Pointer<Void>,
              Pointer<Void>,
              Pointer<Void>,
              int,
              Pointer<_Blob>,
            )
          >(protect ? 'CryptProtectData' : 'CryptUnprotectData');
      // CRYPTPROTECT_UI_FORBIDDEN; machine-wide protection is deliberately absent.
      if (call(input, nullptr, nullptr, nullptr, nullptr, 1, output) == 0) {
        throw StateError('Windows could not protect/unprotect the credential');
      }
      return Uint8List.fromList(output.ref.data.asTypedList(output.ref.length));
    } finally {
      if (data != nullptr) {
        data.asTypedList(bytes.length).fillRange(0, bytes.length, 0);
        _free(_heap, 0, data.cast());
      }
      if (output != nullptr) {
        if (output.ref.data != nullptr) {
          output.ref.data
              .asTypedList(output.ref.length)
              .fillRange(0, output.ref.length, 0);
          _localFree(output.ref.data.cast());
        }
        _free(_heap, 0, output.cast());
      }
      if (input != nullptr) _free(_heap, 0, input.cast());
    }
  }
}
