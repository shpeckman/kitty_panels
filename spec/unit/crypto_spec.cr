# spec/unit/crypto_spec.cr
require "../spec_helper"

private def hex(text : String) : Bytes
  text.hexbytes
end

describe KittyPanels::Crypto do
  describe "base85" do
    {
      ""                                             => "",
      "hello"                                        => "Xk~0{Zv",
      "\u0000\u0001\u0002\u0003\u0004\u0005\u0006\a" => "009C61O)~M",
    }.each do |plain, encoded|
      it "matches Python's b85encode for #{plain.bytesize} bytes" do
        KittyPanels::Crypto.b85_encode(plain.to_slice).should eq(encoded)
        KittyPanels::Crypto.b85_decode(encoded).should eq(plain.to_slice)
      end
    end

    it "round-trips every length from 0 to 40" do
      41.times do |size|
        data = Random::Secure.random_bytes(size)
        KittyPanels::Crypto.b85_decode(KittyPanels::Crypto.b85_encode(data)).should eq(data)
      end
    end

    it "rejects invalid input" do
      expect_raises(KittyPanels::Crypto::Error) { KittyPanels::Crypto.b85_decode("a") }
      expect_raises(KittyPanels::Crypto::Error) { KittyPanels::Crypto.b85_decode("ab\"cd") }
    end
  end

  describe "x25519" do
    it "matches RFC 7748 section 5.2 test vector 1" do
      scalar = hex("a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4")
      point  = hex("e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c")
      KittyPanels::Crypto.x25519(scalar, point).hexstring.should eq("c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552")
    end

    it "matches the RFC 7748 section 6.1 Diffie-Hellman exchange" do
      alice     = hex("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a")
      bob       = hex("5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb")
      basepoint = Bytes.new(32) { |i| i == 0 ? 9_u8 : 0_u8 }
      alice_pub = KittyPanels::Crypto.x25519(alice, basepoint)
      bob_pub   = KittyPanels::Crypto.x25519(bob, basepoint)
      alice_pub.hexstring.should eq("8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a")
      bob_pub.hexstring.should eq("de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f")
      shared = "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742"
      KittyPanels::Crypto.x25519(alice, bob_pub).hexstring.should eq(shared)
      KittyPanels::Crypto.x25519(bob, alice_pub).hexstring.should eq(shared)
    end

    it "rejects inputs of the wrong size" do
      expect_raises(KittyPanels::Crypto::Error) { KittyPanels::Crypto.x25519(Bytes.new(31), Bytes.new(32)) }
    end
  end

  describe "aes-256-gcm" do
    it "round-trips and detects tampering" do
      key   = Random::Secure.random_bytes(32)
      iv    = Random::Secure.random_bytes(12)
      plain = "panel payload".to_slice
      ciphertext, tag = KittyPanels::Crypto.aes256gcm_encrypt(key, iv, plain)
      ciphertext.should_not eq(plain)
      KittyPanels::Crypto.aes256gcm_decrypt(key, iv, tag, ciphertext).should eq(plain)
      tampered = ciphertext.dup
      tampered[0] ^= 1_u8
      expect_raises(KittyPanels::Crypto::Error, /authentication failed/) do
        KittyPanels::Crypto.aes256gcm_decrypt(key, iv, tag, tampered)
      end
    end
  end

  describe "command encryption" do
    it "produces an envelope the key owner can decrypt" do
      private_key, public_key = KittyPanels::Crypto.generate_keypair
      previous = ENV["KITTY_PUBLIC_KEY"]?
      ENV["KITTY_PUBLIC_KEY"] = "1:#{KittyPanels::Crypto.b85_encode(public_key)}"
      begin
        version  = [0, 34, 0].map { |n| JSON::Any.new(n.to_i64) }
        envelope = KittyPanels::Crypto.encrypt_command(%({"cmd":"ls"}), "s3cret", version)
        envelope.keys.sort!.should eq(["encrypted", "iv", "pubkey", "tag", "version"])
        inner = KittyPanels::Crypto.decrypt_command(JSON.parse(envelope.to_json), private_key)
        inner["cmd"].as_s.should eq("ls")
        inner["password"].as_s.should eq("s3cret")
        inner["timestamp"].as_i64.should be_close(Time.utc.to_unix * 1_000_000_000_i64, 5_000_000_000_i64)
      ensure
        ENV["KITTY_PUBLIC_KEY"] = previous
      end
    end

    it "refuses to encrypt without kitty's public key" do
      previous = ENV["KITTY_PUBLIC_KEY"]?
      ENV.delete("KITTY_PUBLIC_KEY")
      begin
        expect_raises(KittyPanels::Crypto::Error, /KITTY_PUBLIC_KEY/) do
          KittyPanels::Crypto.encrypt_command("{}", "pw", [] of JSON::Any)
        end
      ensure
        ENV["KITTY_PUBLIC_KEY"] = previous
      end
    end
  end
end
