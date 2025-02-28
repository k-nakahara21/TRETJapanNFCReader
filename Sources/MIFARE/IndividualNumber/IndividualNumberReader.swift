//
//  IndividualNumberReader.swift
//  TRETJapanNFCReader
//
//  Created by treastrain on 2020/05/10.
//  Copyright © 2020 treastrain / Tanaka Ryoga. All rights reserved.
//

#if os(iOS)
import CoreNFC
#if canImport(TRETJapanNFCReader_Core)
import TRETJapanNFCReader_Core
#endif
#if canImport(TRETJapanNFCReader_MIFARE)
import TRETJapanNFCReader_MIFARE
#endif

@available(iOS 13.0, *)
internal typealias IndividualNumberCardTag = NFCISO7816Tag

@available(iOS 13.0, *)
public class IndividualNumberReader: MiFareReader {
    
    internal let delegate: IndividualNumberReaderSessionDelegate?
    private var items: [IndividualNumberCardItem] = []
    private var IndividualNumberCardExecuteType: IndividualNumberCardExecuteType?
    private var cardInfoInputSupportAppPIN: [UInt8] = []
    private var userAuthenticationPIN: [UInt8] = []
    
    private var lookupRemainingPINType: IndividualNumberCardPINType?
    private var dataToSign: [UInt8] = []
    
    private init() {
        fatalError()
    }
    
    /// IndividualNumberReader を初期化する。
    /// - Parameter delegate: IndividualNumberReaderDelegate
    public init(delegate: IndividualNumberReaderSessionDelegate) {
        self.delegate = delegate
        super.init(delegate: delegate)
    }
    
    /// マイナンバーカードからデータを読み取る
    /// - Parameters:
    ///   - items: マイナンバーカードから読み取りたいデータ
    ///   - cardInfoInputSupportAppPIN: 券面事項入力補助用暗証番号
    public func get(items: [IndividualNumberCardItem], cardInfoInputSupportAppPIN: String = "") {
        self.IndividualNumberCardExecuteType = .getCardInfoInput
        self.items = items
        
        if let cardInfoInputSupportAppPIN = cardInfoInputSupportAppPIN.data(using: .utf8) {
            self.cardInfoInputSupportAppPIN = [UInt8](cardInfoInputSupportAppPIN)
        }
        
        self.beginScanning()
    }
    
    /// マイナンバーカードの暗証番号残り試行回数を読み取る
    /// - Parameter pinType: 読み取りたい対象の暗証番号の種類
    public func lookupRemainingPIN(pinType: IndividualNumberCardPINType) {
        self.IndividualNumberCardExecuteType = .lookupRemainingPIN
        self.lookupRemainingPINType = pinType
        self.beginScanning()
    }
    
    /// マイナンバーカードで利用者証明用電子署名を生成する
    /// - Parameters:
    ///   - userAuthenticationPIN: 利用者証明用秘密鍵用暗証番号
    ///   - dataToSign: 署名対象データ
    public func computeDigitalSignatureForUserAuthentication(userAuthenticationPIN: String = "",dataToSign: [UInt8]) {
        self.IndividualNumberCardExecuteType = .computeDigitalSignature
        if let userAuthenticationPIN = userAuthenticationPIN.data(using: .utf8){
            self.userAuthenticationPIN = [UInt8](userAuthenticationPIN)
        }
        self.dataToSign = dataToSign
        self.beginScanning()
    }
    
    /// 利用者証明用電子証明書を読み取る
    public func getElectronicCertificateForUserVerification() {
        self.IndividualNumberCardExecuteType = .getDigitalCertificateForUserVerification
        self.beginScanning()
    }
    
    private func beginScanning() {
        guard self.checkReadingAvailable() else {
            print("""
                ------------------------------------------------------------
                【マイナンバーカードを読み取るには】
                マイナンバーカードを読み取るには、開発している iOS Application の Info.plist に "ISO7816 application identifiers for NFC Tag Reader Session (com.apple.developer.nfc.readersession.iso7816.select-identifiers)" を追加します。ISO7816 application identifiers for NFC Tag Reader Session には以下を含める必要があります。
                \t• Item 0: D392F000260100000001
                \t• Item 1: D3921000310001010408
                \t• Item 2: D3921000310001010100
                \t• Item 3: D3921000310001010401
                ------------------------------------------------------------
            """)
            return
        }
        
        self.session = NFCTagReaderSession(pollingOption: .iso14443, delegate: self)
        self.session?.alertMessage = Localized.nfcReaderSessionAlertMessage.string()
        self.session?.begin()
    }
    
    public override func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        super.tagReaderSession(session, didInvalidateWithError: error)
        if let readerError = error as? NFCReaderError {
            if (readerError.code != .readerSessionInvalidationErrorFirstNDEFTagRead)
                && (readerError.code != .readerSessionInvalidationErrorUserCanceled) {
                print("""
                    ------------------------------------------------------------
                    【マイナンバーカードを読み取るには】
                    マイナンバーカードを読み取るには、開発している iOS Application の Info.plist に "ISO7816 application identifiers for NFC Tag Reader Session (com.apple.developer.nfc.readersession.iso7816.select-identifiers)" を追加します。ISO7816 application identifiers for NFC Tag Reader Session には以下を含める必要があります。
                    \t• Item 0: D392F000260100000001
                    \t• Item 1: D3921000310001010408
                    \t• Item 2: D3921000310001010100
                    \t• Item 3: D3921000310001010401
                    ------------------------------------------------------------
                """)
            }
        }
        self.delegate?.japanNFCReaderSession(didInvalidateWithError: error)
    }
    
    public override func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        
        if tags.count > 1 {
            let retryInterval = DispatchTimeInterval.milliseconds(1000)
            let alertedMessage = session.alertMessage
            session.alertMessage = Localized.nfcTagReaderSessionDidDetectTagsMoreThan1TagIsDetectedMessage.string()
            DispatchQueue.global().asyncAfter(deadline: .now() + retryInterval, execute: {
                session.restartPolling()
                session.alertMessage = alertedMessage
            })
            return
        }
        
        let tag = tags.first!
        
        session.connect(to: tag) { (error) in
            if nil != error {
                session.invalidate(errorMessage: Localized.nfcTagReaderSessionConnectErrorMessage.string())
                return
            }
            
            guard case NFCTag.iso7816(let individualNumberCardTag) = tag else {
                let retryInterval = DispatchTimeInterval.milliseconds(1000)
                let alertedMessage = session.alertMessage
                session.alertMessage = Localized.nfcTagReaderSessionDifferentTagTypeErrorMessage.string()
                DispatchQueue.global().asyncAfter(deadline: .now() + retryInterval, execute: {
                    session.restartPolling()
                    session.alertMessage = alertedMessage
                })
                return
            }
            
            switch individualNumberCardTag.initialSelectedAID {
            case "D392F000260100000001", "D3921000310001010408", "D3921000310001010100", "D3921000310001010401":
                break
            default:
                let retryInterval = DispatchTimeInterval.milliseconds(1000)
                let alertedMessage = session.alertMessage
                session.alertMessage = Localized.nfcTagReaderSessionDifferentTagTypeErrorMessage.string()
                DispatchQueue.global().asyncAfter(deadline: .now() + retryInterval, execute: {
                    session.restartPolling()
                    session.alertMessage = alertedMessage
                })
                return
            }
            
            session.alertMessage = Localized.nfcTagReaderSessionReadingMessage.string()
            
            let individualNumberCard = IndividualNumberCard(tag: individualNumberCardTag, data: IndividualNumberCardData())
            
            self.executeWithADPUFunction(session, individualNumberCardTag, individualNumberCard) { (individualNumberCard) in
                session.alertMessage = Localized.nfcTagReaderSessionDoneMessage.string()
                session.invalidate()
                
                self.delegate?.individualNumberReaderSession(didRead: individualNumberCard.data)
            }
        }
    }
    
    private func executeWithADPUFunction(_ session: NFCTagReaderSession,_ individualNumberCardTag: NFCISO7816Tag, _ individualNumberCard: IndividualNumberCard, completion: @escaping (IndividualNumberCard) -> Void){
        var individualNumberCard = individualNumberCard
        DispatchQueue(label: "TRETJPNRIndividualNumberReader", qos: .default).async {
            switch self.IndividualNumberCardExecuteType {
            case .getCardInfoInput:
                for item in self.items {
                    switch item {
                    case .tokenInfo:
                        individualNumberCard = self.readJPKIToken(session, individualNumberCard)
                    case .individualNumber:
                        individualNumberCard = self.readIndividualNumber(session, individualNumberCard, cardInfoInputSupportAppPIN: self.cardInfoInputSupportAppPIN)
                    }
                }
            case .computeDigitalSignature:
                individualNumberCard = self.getElectronicCertificateForUserVerification(session, individualNumberCard)
                individualNumberCard = self.computeDigitalSignatureForUserAuthentication(session, individualNumberCard, userAuthenticationPIN: self.userAuthenticationPIN, dataToSign: self.dataToSign)
            case .getDigitalCertificateForUserVerification:
                individualNumberCard = self.getElectronicCertificateForUserVerification(session, individualNumberCard)
            case .lookupRemainingPIN:
                if let pinType = self.lookupRemainingPINType{
                    individualNumberCard = self.lookupRemainingPIN(session, individualNumberCard, pinType)
                }
            case .none:
                break
            }
            completion(individualNumberCard)
        }
    }
}

#endif
