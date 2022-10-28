//
//  URRegistry.swift
//
//
//  Created by Zhiying Fan on 26/8/2022.
//

import Foundation
import URRegistryFFI

public class URRegistry {
    public static let shared = URRegistry()
    
    public var nextPartUnsignedUR: String? {
        guard let urEncoderPointer = urEncoderPointer else { return nil }
        
        let qrValuePtr = URRegistryFFI.ur_encoder_next_part(urEncoderPointer).pointee.safeValue?._string
        
        guard let qrValuePtr = qrValuePtr else { return nil }
        
        return String(cString: qrValuePtr).uppercased()
    }
        
    private var decoderPointer = UnsafeMutableRawPointer(mutating: URRegistryFFI.ur_decoder_new().pointee.safeValue?._object)
    private var urEncoderPointer: UnsafeMutableRawPointer?
    
    private init() {}
    
    /// Get a parent CryptoHDKey instance provided by a UR, which can be used to derive public keys
    /// - Parameter ur: An UR string
    /// - Returns: An instance of CryptoHDKey
    public func getSourceHDKey(from ur: String) -> CryptoHDKey? {
        guard ur.starts(with: "UR:CRYPTO-HDKEY") else { return nil }
        
        let decoderPointer = UnsafeMutableRawPointer(mutating: URRegistryFFI.ur_decoder_new().pointee.safeValue?._object)
        let urPointer = UnsafeMutableRawPointer(mutating: (ur as NSString).utf8String)
        let targetPointer = UnsafeMutableRawPointer(mutating: ("crypto-hdkey" as NSString).utf8String)
        
        URRegistryFFI.ur_decoder_receive(decoderPointer, urPointer)
        
        let isCompleted = URRegistryFFI.ur_decoder_is_complete(decoderPointer).pointee.safeValue?._boolean ?? false
        
        guard isCompleted else { return nil }
        
        let hdKeyPtr = URRegistryFFI.ur_decoder_resolve(decoderPointer, targetPointer).pointee.safeValue?._object
        let hdKeyPointer = UnsafeMutableRawPointer(mutating: hdKeyPtr)
        
        let keyPtr = URRegistryFFI.crypto_hd_key_get_key_data(hdKeyPointer).pointee.safeValue?._string
        let chainCodePtr = URRegistryFFI.crypto_hd_key_get_chain_code(hdKeyPointer).pointee.safeValue?._string
        let sourceFingerprintPtr = URRegistryFFI.crypto_hd_key_get_source_fingerprint(hdKeyPointer).pointee.safeValue?._string
        let notePtr = URRegistryFFI.crypto_hd_key_get_note(hdKeyPointer).pointee.safeValue?._string
        
        guard
            let keyPtr = keyPtr,
            let chainCodePtr = chainCodePtr,
            let sourceFingerprintPtr = sourceFingerprintPtr,
            let sourceFingerprint = UInt32(String(cString: sourceFingerprintPtr), radix: 16),
            let notePtr = notePtr
        else { return nil }
        
        let key = String(cString: keyPtr)
        let chainCode = String(cString: chainCodePtr)
        let noteString = String(cString: notePtr)
        let note = CryptoHDKey.Note(rawValue: noteString) ?? .standard
        return CryptoHDKey(key: key, chainCode: chainCode, sourceFingerprint: sourceFingerprint, note: note)
    }
    
    /// Create a new decoder to clean the received UR on the current decoder. Please make sure to call this method after finishing a decoding process or before starting a new decoding task.
    public func resetDecoder() {
        decoderPointer = UnsafeMutableRawPointer(mutating: URRegistryFFI.ur_decoder_new().pointee.safeValue?._object)
    }
    
    /// Get a list of CryptoHDKey provided by a UR, they can not be used to derive key
    /// - Parameter ur: An UR string
    /// - Returns: A list of CryptoHDKey
    public func getHDKeys(from ur: String) -> [CryptoHDKey]? {
        guard ur.starts(with: "UR:CRYPTO-ACCOUNT") else { return nil }
        
        let urPointer = UnsafeMutableRawPointer(mutating: (ur as NSString).utf8String)
        let targetPointer = UnsafeMutableRawPointer(mutating: ("crypto-account" as NSString).utf8String)
        
        URRegistryFFI.ur_decoder_receive(decoderPointer, urPointer)
        
        let isCompleted = URRegistryFFI.ur_decoder_is_complete(decoderPointer).pointee.safeValue?._boolean ?? false
        
        guard isCompleted else { return nil }
        
        let accountPtr = URRegistryFFI.ur_decoder_resolve(decoderPointer, targetPointer).pointee.safeValue?._object
        let accountPointer = UnsafeMutableRawPointer(mutating: accountPtr)
        
        var hdKeyPtrs = [PtrVoid?]()
        let length = URRegistryFFI.crypto_account_get_accounts_len(accountPointer).pointee.safeValue?._uint32 ?? 0
        for index in 0..<length {
            let outPutPtr = URRegistryFFI.crypto_account_get_account(accountPointer, index).pointee.safeValue?._object
            let outPutPointer = UnsafeMutableRawPointer(mutating: outPutPtr)
            let hdKeyPtr = URRegistryFFI.crypto_output_get_hd_key(outPutPointer).pointee.safeValue?._object
            hdKeyPtrs.append(hdKeyPtr)
        }
        
        var hdKeys = [CryptoHDKey]()
        for hdKeyPtr in hdKeyPtrs {
            let hdKeyPointer = UnsafeMutableRawPointer(mutating: hdKeyPtr)
            
            let keyPtr = URRegistryFFI.crypto_hd_key_get_key_data(hdKeyPointer).pointee.safeValue?._string
            let sourceFingerprintPtr = URRegistryFFI.crypto_hd_key_get_source_fingerprint(hdKeyPointer).pointee.safeValue?._string
            let notePtr = URRegistryFFI.crypto_hd_key_get_note(hdKeyPointer).pointee.safeValue?._string
            
            guard
                let keyPtr = keyPtr,
                let sourceFingerprintPtr = sourceFingerprintPtr,
                let sourceFingerprint = UInt32(String(cString: sourceFingerprintPtr), radix: 16),
                let notePtr = notePtr
            else { continue }
            
            let key = String(cString: keyPtr)
            let noteString = String(cString: notePtr)
            let note = CryptoHDKey.Note(rawValue: noteString) ?? .standard
            let hdKey = CryptoHDKey(key: key, chainCode: nil, sourceFingerprint: sourceFingerprint, note: note)
            hdKeys.append(hdKey)
        }
        
        return hdKeys
    }
    
    /// Uncompress public key
    /// - Parameter compressedKey: Compressed public key
    /// - Returns: The uncompressed public key
    public func getUncompressedKey(from compressedKey: String) -> String? {
        let keyPointer = UnsafeMutableRawPointer(mutating: (compressedKey as NSString).utf8String)
        let keyPtr = URRegistryFFI.crypto_hd_key_get_uncompressed_key_data(keyPointer).pointee.safeValue?._string
        
        guard let keyPtr = keyPtr else { return nil }
        return String(cString: keyPtr)
    }
    
    /// Get a sign request UR encoder and set it to urEncoderPointer for getting nextPartUnsignedUR
    /// - Parameter signRequest: A KeystoneSignRequest holding all of the required information
    public func setSignRequestUREncoder(with signRequest: KeystoneSignRequest) {
        let requestIdPointer = UnsafeMutableRawPointer(mutating: (signRequest.requestId as NSString).utf8String)
        let signDataPointer = UnsafeMutableRawPointer(mutating: (signRequest.signData as NSString).utf8String)
        let pathPointer = UnsafeMutableRawPointer(mutating: (signRequest.path as NSString).utf8String)
        let addressPointer = UnsafeMutableRawPointer(mutating: (signRequest.address as NSString).utf8String)
        let originPointer = UnsafeMutableRawPointer(mutating: (signRequest.origin as NSString).utf8String)
        
        let ethSignRequest = URRegistryFFI.eth_sign_request_construct(
            requestIdPointer,
            signDataPointer,
            UInt32(signRequest.signType.rawValue),
            signRequest.chainId,
            pathPointer,
            signRequest.xfp,
            addressPointer,
            originPointer
        )
        
        let ethSignRequestPtr = ethSignRequest?.pointee.safeValue?._object
        let ethSignRequestPointer = UnsafeMutableRawPointer(mutating: ethSignRequestPtr)
        let urEncoderPtr = URRegistryFFI.eth_sign_request_get_ur_encoder(ethSignRequestPointer).pointee.safeValue?._object
        urEncoderPointer = UnsafeMutableRawPointer(mutating: urEncoderPtr)
    }
    
    /// Get signature information provided by a UR
    /// - Parameter ur: An UR string
    /// - Returns: The hex string of the signature
    public func getSignature(from ur: String) -> KeystoneSignature? {
        let decoderPtr = URRegistryFFI.ur_decoder_new().pointee.safeValue?._object
        let decoderPointer = UnsafeMutableRawPointer(mutating: decoderPtr)
        let urPointer = UnsafeMutableRawPointer(mutating: (ur as NSString).utf8String)
        let targetPointer = UnsafeMutableRawPointer(mutating: ("eth-signature" as NSString).utf8String)
        
        URRegistryFFI.ur_decoder_receive(decoderPointer, urPointer)
        
        let isCompleted = URRegistryFFI.ur_decoder_is_complete(decoderPointer).pointee.safeValue?._boolean ?? false
        
        guard isCompleted else { return nil }
        
        let ethSignaturePtr = URRegistryFFI.ur_decoder_resolve(decoderPointer, targetPointer).pointee.safeValue?._object
        let ethSignaturePtrPointer = UnsafeMutableRawPointer(mutating: ethSignaturePtr)
        
        let signaturePtr = URRegistryFFI.eth_signature_get_signature(ethSignaturePtrPointer).pointee.safeValue?._string
        let requestIdPtr = URRegistryFFI.eth_signature_get_request_id(ethSignaturePtrPointer).pointee.safeValue?._string
        
        guard
            let signaturePtr = signaturePtr,
            let requestIdPtr = requestIdPtr
        else { return nil }
        
        let signature = String(cString: signaturePtr)
        let requestId = String(cString: requestIdPtr)
        
        return KeystoneSignature(requestId: requestId, signature: signature)
    }
}

extension Response {
    var safeValue: Value? {
        if status_code == 0 {
            return value
        } else {
            fatalError("Error: \(String(cString: error_message))")
        }
    }
}
