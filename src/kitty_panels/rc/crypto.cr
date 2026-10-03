# src/kitty_panels/rc/crypto.cr
require "openssl"
require "big"
require "random/secure"
require "digest/sha256"

lib LibCrypto
  fun evp_encrypt_init_ex = EVP_EncryptInit_ex(ctx : EVP_CIPHER_CTX, cipher : EVP_CIPHER, engine : Void*, key : UInt8*, iv : UInt8*) : LibC::Int
  fun evp_encrypt_update = EVP_EncryptUpdate(ctx : EVP_CIPHER_CTX, out : UInt8*, outlen : LibC::Int*, in : UInt8*, inlen : LibC::Int) : LibC::Int
  fun evp_encrypt_final_ex = EVP_EncryptFinal_ex(ctx : EVP_CIPHER_CTX, out : UInt8*, outlen : LibC::Int*) : LibC::Int
  fun evp_decrypt_init_ex = EVP_DecryptInit_ex(ctx : EVP_CIPHER_CTX, cipher : EVP_CIPHER, engine : Void*, key : UInt8*, iv : UInt8*) : LibC::Int
  fun evp_decrypt_update = EVP_DecryptUpdate(ctx : EVP_CIPHER_CTX, out : UInt8*, outlen : LibC::Int*, in : UInt8*, inlen : LibC::Int) : LibC::Int
  fun evp_decrypt_final_ex = EVP_DecryptFinal_ex(ctx : EVP_CIPHER_CTX, out : UInt8*, outlen : LibC::Int*) : LibC::Int
  fun evp_cipher_ctx_ctrl = EVP_CIPHER_CTX_ctrl(ctx : EVP_CIPHER_CTX, type : LibC::Int, arg : LibC::Int, ptr : Void*) : LibC::Int
  fun evp_cipher_ctx_free = EVP_CIPHER_CTX_free(ctx : EVP_CIPHER_CTX) : Void
end

module KittyPanels::Crypto
  extend self

  B85_ALPHABET  = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz!#$%&()*+-;<=>?@^_`{|}~"
  GCM_IV_BYTES  =   12
  GCM_TAG_BYTES =   16
  GCM_SET_IVLEN = 0x09
  GCM_GET_TAG   = 0x10
  GCM_SET_TAG   = 0x11

  private CURVE_P      = BigInt.new(2) ** 255 - 19
  private CURVE_A24    = BigInt.new(121665)
  private CURVE_INV_EX = CURVE_P - 2
  private BASEPOINT    = Bytes.new(32) { |i| i == 0 ? 9_u8 : 0_u8 }

  class Error < Exception
  end

  def b85_encode(data : Bytes) : String
    String.build do |io|
      offset = 0
      while offset < data.size
        remaining = data.size - offset
        width     = Math.min(remaining, 4)
        value     = 0_u32
        4.times { |i| value = (value << 8) | (i < width ? data[offset + i].to_u32 : 0_u32) }
        chars = Bytes.new(5)
        4.downto(0) do |i|
          chars[i] = B85_ALPHABET[(value % 85).to_i].ord.to_u8
          value //= 85
        end
        io.write(width == 4 ? chars : chars[0, width + 1])
        offset += width
      end
    end
  end

  def b85_decode(text : String) : Bytes
    raise Error.new("invalid base85 length") if text.bytesize % 5 == 1
    io     = IO::Memory.new
    offset = 0
    while offset < text.bytesize
      remaining = text.bytesize - offset
      width     = Math.min(remaining, 5)
      value     = 0_u64
      5.times do |i|
        char  = i < width ? text.byte_at(offset + i).chr : B85_ALPHABET[-1]
        digit = B85_ALPHABET.index(char) || raise(Error.new("invalid base85 character '#{char}'"))
        value = value * 85 + digit
      end
      raise Error.new("base85 chunk overflow") if value > 0xFFFFFFFF_u64
      bytes = Bytes.new(4) { |i| ((value >> (8 * (3 - i))) & 0xFF).to_u8 }
      io.write(width == 5 ? bytes : bytes[0, width - 1])
      offset += width
    end
    io.to_slice
  end

  def x25519(scalar : Bytes, point : Bytes) : Bytes
    raise Error.new("x25519 inputs must be 32 bytes") unless scalar.size == 32 && point.size == 32
    k = scalar.dup
    k[0] &= 248
    k[31] = (k[31] & 127) | 64
    u = point.dup
    u[31] &= 127
    x1   = le_to_big(u)
    x2   = BigInt.new(1)
    z2   = BigInt.new(0)
    x3   = x1
    z3   = BigInt.new(1)
    swap = 0
    255.downto(0) do |t|
      kt = (k[t // 8].to_i >> (t % 8)) & 1
      swap ^= kt
      if swap == 1
        x2, x3 = x3, x2
        z2, z3 = z3, z2
      end
      swap = kt
      a    = pmod(x2 + z2)
      aa   = pmod(a * a)
      b    = pmod(x2 - z2)
      bb   = pmod(b * b)
      e    = pmod(aa - bb)
      c    = pmod(x3 + z3)
      d    = pmod(x3 - z3)
      da   = pmod(d * a)
      cb   = pmod(c * b)
      x3   = pmod((da + cb) * (da + cb))
      z3   = pmod(x1 * pmod((da - cb) * (da - cb)))
      x2   = pmod(aa * bb)
      z2   = pmod(e * (aa + CURVE_A24 * e))
    end
    if swap == 1
      x2, x3 = x3, x2
      z2, z3 = z3, z2
    end
    big_to_le(pmod(x2 * powmod(z2, CURVE_INV_EX)), 32)
  end

  def generate_keypair : Tuple(Bytes, Bytes)
    private_key = Random::Secure.random_bytes(32)
    {private_key, x25519(private_key, BASEPOINT)}
  end

  def derive_secret(private_key : Bytes, peer_public : Bytes) : Bytes
    Digest::SHA256.digest { |ctx| ctx.update(x25519(private_key, peer_public)) }
  end

  def encrypt_command(command_json : String, password : String, version : Array(JSON::Any)) : Hash(String, JSON::Any)
    protocol, pubkey_b85 = parse_public_key_env
    raise Error.new("unsupported KITTY_PUBLIC_KEY protocol: #{protocol}") unless protocol == "1"
    private_key, public_key = generate_keypair
    secret  = derive_secret(private_key, b85_decode(pubkey_b85))
    iv      = Random::Secure.random_bytes(GCM_IV_BYTES)
    now     = Time.utc
    payload = JSON.parse(command_json).as_h
    payload["password"] = JSON::Any.new(password)
    payload["timestamp"] = JSON::Any.new(now.to_unix * 1_000_000_000_i64 + now.nanosecond.to_i64)
    ciphertext, tag = aes256gcm_encrypt(secret, iv, payload.to_json.to_slice)
    {
      "version"   => JSON::Any.new(version),
      "iv"        => JSON::Any.new(b85_encode(iv)),
      "tag"       => JSON::Any.new(b85_encode(tag)),
      "pubkey"    => JSON::Any.new(b85_encode(public_key)),
      "encrypted" => JSON::Any.new(b85_encode(ciphertext)),
    }
  end

  def decrypt_command(outer : JSON::Any, private_key : Bytes) : JSON::Any
    fields   = outer.as_h
    protocol = fields["enc_proto"]?.try(&.as_s?) || "1"
    raise Error.new("unsupported encryption protocol: #{protocol}") unless protocol == "1"
    secret     = derive_secret(private_key, b85_decode(fields["pubkey"].as_s))
    iv         = b85_decode(fields["iv"].as_s)
    tag        = b85_decode(fields["tag"].as_s)
    ciphertext = b85_decode(fields["encrypted"].as_s)
    plain      = aes256gcm_decrypt(secret, iv, tag, ciphertext)
    JSON.parse(String.new(plain))
  end

  def aes256gcm_encrypt(key : Bytes, iv : Bytes, plaintext : Bytes) : Tuple(Bytes, Bytes)
    raise Error.new("aes-256-gcm key must be 32 bytes") unless key.size == 32
    ctx = gcm_ctx(key, iv, encrypt: true)
    begin
      ciphertext = Bytes.new(plaintext.size + 16)
      outlen     = 0
      check LibCrypto.evp_encrypt_update(ctx, ciphertext, pointerof(outlen), plaintext, plaintext.size)
      total = outlen
      check LibCrypto.evp_encrypt_final_ex(ctx, ciphertext + total, pointerof(outlen))
      total += outlen
      tag = Bytes.new(GCM_TAG_BYTES)
      check LibCrypto.evp_cipher_ctx_ctrl(ctx, GCM_GET_TAG, GCM_TAG_BYTES, tag)
      {ciphertext[0, total], tag}
    ensure
      LibCrypto.evp_cipher_ctx_free(ctx)
    end
  end

  def aes256gcm_decrypt(key : Bytes, iv : Bytes, tag : Bytes, ciphertext : Bytes) : Bytes
    raise Error.new("aes-256-gcm key must be 32 bytes") unless key.size == 32
    ctx = gcm_ctx(key, iv, encrypt: false)
    begin
      plain  = Bytes.new(ciphertext.size + 16)
      outlen = 0
      check LibCrypto.evp_decrypt_update(ctx, plain, pointerof(outlen), ciphertext, ciphertext.size)
      total = outlen
      check LibCrypto.evp_cipher_ctx_ctrl(ctx, GCM_SET_TAG, tag.size, tag)
      unless LibCrypto.evp_decrypt_final_ex(ctx, plain + total, pointerof(outlen)) == 1
        raise Error.new("aes-256-gcm authentication failed")
      end
      total += outlen
      plain[0, total]
    ensure
      LibCrypto.evp_cipher_ctx_free(ctx)
    end
  end

  private def gcm_ctx(key : Bytes, iv : Bytes, encrypt : Bool) : LibCrypto::EVP_CIPHER_CTX
    cipher = LibCrypto.evp_get_cipherbyname("aes-256-gcm")
    raise Error.new("aes-256-gcm not available in libcrypto") if cipher.null?
    ctx = LibCrypto.evp_cipher_ctx_new
    raise Error.new("failed to allocate cipher context") if ctx.null?
    if encrypt
      check LibCrypto.evp_encrypt_init_ex(ctx, cipher, nil, nil, nil)
      check LibCrypto.evp_cipher_ctx_ctrl(ctx, GCM_SET_IVLEN, iv.size, nil)
      check LibCrypto.evp_encrypt_init_ex(ctx, cipher, nil, key, iv)
    else
      check LibCrypto.evp_decrypt_init_ex(ctx, cipher, nil, nil, nil)
      check LibCrypto.evp_cipher_ctx_ctrl(ctx, GCM_SET_IVLEN, iv.size, nil)
      check LibCrypto.evp_decrypt_init_ex(ctx, cipher, nil, key, iv)
    end
    ctx
  end

  private def check(result : LibC::Int) : Nil
    raise Error.new("libcrypto EVP operation failed") unless result == 1
  end

  private def parse_public_key_env : Tuple(String, String)
    raw   = ENV["KITTY_PUBLIC_KEY"]?.presence || raise(Error.new("KITTY_PUBLIC_KEY is not set, cannot encrypt"))
    parts = raw.split(':', 2)
    raise Error.new("malformed KITTY_PUBLIC_KEY") if parts.size != 2
    {parts[0], parts[1]}
  end

  private def pmod(value : BigInt) : BigInt
    result = value % CURVE_P
    result < 0 ? result + CURVE_P : result
  end

  private def powmod(base : BigInt, exponent : BigInt) : BigInt
    result = BigInt.new(1)
    b      = pmod(base)
    e      = exponent
    while e > 0
      result = pmod(result * b) if e.odd?
      b      = pmod(b * b)
      e >>= 1
    end
    result
  end

  private def le_to_big(bytes : Bytes) : BigInt
    value = BigInt.new(0)
    (bytes.size - 1).downto(0) { |i| value = (value << 8) | bytes[i] }
    value
  end

  private def big_to_le(value : BigInt, size : Int32) : Bytes
    Bytes.new(size) do |i|
      ((value >> (8 * i)) & 0xFF).to_i.to_u8
    end
  end
end
