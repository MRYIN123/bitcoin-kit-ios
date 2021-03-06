import XCTest
import Cuckoo
import RealmSwift
import RxSwift
@testable import HSBitcoinKit

class InitialSyncerTests: XCTestCase {

    private var mockRealmFactory: MockIRealmFactory!
    private var mockStateManager: MockIStateManager!
    private var mockHDWallet: MockIHDWallet!
    private var mockInitialSyncApi: MockIInitialSyncApi!
    private var mockAddressManager: MockIAddressManager!
    private var mockAddressSelector: MockIAddressSelector!
    private var mockFactory: MockIFactory!
    private var mockPeerGroup: MockIPeerGroup!
    private var mockNetwork: MockINetwork!
    private var mockListener: MockISyncStateListener!
    private var syncer: InitialSyncer!

    private var realm: Realm!
    private var internalKeys: [PublicKey]!
    private var externalKeys: [PublicKey]!
    private var internalAddresses: [String]!
    private var externalAddresses: [String]!

    override func setUp() {
        super.setUp()

        mockRealmFactory = MockIRealmFactory()
        mockHDWallet = MockIHDWallet()
        mockStateManager = MockIStateManager()
        mockInitialSyncApi = MockIInitialSyncApi()
        mockAddressManager = MockIAddressManager()
        mockAddressSelector = MockIAddressSelector()
        mockFactory = MockIFactory()
        mockPeerGroup = MockIPeerGroup()
        mockNetwork = MockINetwork()
        mockListener = MockISyncStateListener()

        realm = try! Realm(configuration: Realm.Configuration(inMemoryIdentifier: "TestRealm"))
        try! realm.write { realm.deleteAll() }
        stub(mockRealmFactory) {mock in
            when(mock.realm.get).thenReturn(realm)
        }
        stub(mockNetwork) { mock in
            when(mock.syncableFromApi.get).thenReturn(true)
        }


        internalKeys = []
        externalKeys = []
        internalAddresses = []
        externalAddresses = []
        for account in 0..<2 {
            for i in 0..<5 {
                let internalKey = PublicKey()
                let internalAddress = LegacyAddress(type: .pubKeyHash, keyHash: Data(bytes: [UInt8(1), UInt8(i)]), base58: "internal\(i + (account*5))")
                internalKey.account = account
                internalKey.keyHash = internalAddress.keyHash
                internalKey.external = false
                internalKeys.append(internalKey)
                internalAddresses.append(internalAddress.stringValue)

                let externalKey = PublicKey()
                let externalAddress = LegacyAddress(type: .pubKeyHash, keyHash: Data(bytes: [UInt8(0), UInt8(i)]), base58: "external\(i + (account*5))")
                externalKey.account = account
                externalKey.keyHash = externalAddress.keyHash
                externalKeys.append(externalKey)
                externalAddresses.append(externalAddress.stringValue)
            }
        }

        stub(mockHDWallet) { mock in
            when(mock.gapLimit.get).thenReturn(2)
            for account in 0..<2 {
                for i in 0..<5 {
                    when(mock.publicKey(account: equal(to: account), index: equal(to: i), external: equal(to: false))).thenReturn(internalKeys[i + (account*5)])
                    when(mock.publicKey(account: equal(to: account), index: equal(to: i), external: equal(to: true))).thenReturn(externalKeys[i + (account*5)])
                }
            }
        }
        stub(mockAddressSelector) { mock in
            for i in 0..<(5*2) {
                when(mock.getAddressVariants(publicKey: equal(to: internalKeys[i]))).thenReturn([internalAddresses[i]])
                when(mock.getAddressVariants(publicKey: equal(to: externalKeys[i]))).thenReturn([externalAddresses[i]])
            }
        }
        stub(mockAddressManager) { mock in
            when(mock.addKeys(keys: any())).thenDoNothing()
            when(mock.fillGap()).thenDoNothing()
        }
        stub(mockStateManager) { mock in
            when(mock.restored.get).thenReturn(false)
            when(mock.restored.set(any())).thenDoNothing()
        }
        stub(mockPeerGroup) { mock in
            when(mock.start()).thenDoNothing()
        }
        stub(mockListener) { mock in
            when(mock.syncStarted()).thenDoNothing()
            when(mock.syncStopped()).thenDoNothing()
        }

        let checkpointBlock = Block()
        checkpointBlock.height = 100
        stub(mockNetwork) { mock in
            when(mock.checkpointBlock.get).thenReturn(checkpointBlock)
            when(mock.pubKeyHash.get).thenReturn(UInt8(0x6f))
        }

        syncer = InitialSyncer(
                realmFactory: mockRealmFactory,
                listener: mockListener,
                hdWallet: mockHDWallet,
                stateManager: mockStateManager,
                api: mockInitialSyncApi,
                addressManager: mockAddressManager,
                addressSelector: mockAddressSelector,
                factory: mockFactory,
                peerGroup: mockPeerGroup,
                network: mockNetwork,
                async: false
        )
    }

    override func tearDown() {
        mockRealmFactory = nil
        mockListener = nil
        mockHDWallet = nil
        mockStateManager = nil
        mockInitialSyncApi = nil
        mockAddressManager = nil
        mockAddressSelector = nil
        mockFactory = nil
        mockPeerGroup = nil
        mockNetwork = nil
        syncer = nil

        realm = nil

        super.tearDown()
    }

    func testStartPeerGroupIfAlreadySynced() {
        stub(mockStateManager) { mock in
            when(mock.restored.get).thenReturn(true)
        }

        try! syncer.sync()

        verify(mockPeerGroup).start()
    }

    func testSetApiSyncedIfNetworkNotSyncableFromApi() {
        stub(mockNetwork) { mock in
            when(mock.syncableFromApi.get).thenReturn(false)
        }
        stub(mockStateManager) { mock in
            when(mock.restored.set(any())).thenDoNothing()
            when(mock.restored.get).thenReturn(true)
        }

        try! syncer.sync()

        verify(mockStateManager).restored.set(true)
    }

    func testDontStartSyncSecondTimeBeforeFinished() {
        let firstBlock = TestData.firstBlock
        let firstBlockHash = BlockHash(withHeaderHash: firstBlock.headerHash, height: 10)
        let externalResponse = BlockResponse(hash: firstBlock.reversedHeaderHashHex, height: 10)

        stub(mockInitialSyncApi) { mock in
            when(mock.getBlockHashes(address: equal(to: externalAddresses[0]))).thenReturn(Observable.just([externalResponse]))
            when(mock.getBlockHashes(address: equal(to: externalAddresses[1]))).thenReturn(Observable.just([]).delay(0.001, scheduler: MainScheduler.instance))
            when(mock.getBlockHashes(address: equal(to: externalAddresses[2]))).thenReturn(Observable.just([]))
            when(mock.getBlockHashes(address: equal(to: internalAddresses[0]))).thenReturn(Observable.just([]))
            when(mock.getBlockHashes(address: equal(to: internalAddresses[1]))).thenReturn(Observable.just([]))
        }

        stub(mockFactory) { mock in
            when(mock).blockHash(withHeaderHash: equal(to: firstBlock.headerHash), height: equal(to: externalResponse.height)).thenReturn(firstBlockHash)
        }

        try! syncer.sync()
        verify(mockInitialSyncApi).getBlockHashes(address: equal(to: externalAddresses[0]))

        reset(mockInitialSyncApi)
        stub(mockInitialSyncApi) { mock in
            when(mock.getBlockHashes(address: equal(to: externalAddresses[0]))).thenReturn(Observable.just([externalResponse]))
            when(mock.getBlockHashes(address: equal(to: externalAddresses[1]))).thenReturn(Observable.just([]))
            when(mock.getBlockHashes(address: equal(to: externalAddresses[2]))).thenReturn(Observable.just([]))
            when(mock.getBlockHashes(address: equal(to: internalAddresses[0]))).thenReturn(Observable.just([]))
            when(mock.getBlockHashes(address: equal(to: internalAddresses[1]))).thenReturn(Observable.just([]))
        }

        try! syncer.sync()
        verify(mockInitialSyncApi, never()).getBlockHashes(address: any())
        waitForMainQueue()
    }

    func testStartSyncSecondTimeAfterFinished() {
        stub(mockInitialSyncApi) { mock in
            when(mock.getBlockHashes(address: equal(to: externalAddresses[0]))).thenReturn(Observable.just([]))
            when(mock.getBlockHashes(address: equal(to: externalAddresses[1]))).thenReturn(Observable.just([]))
            when(mock.getBlockHashes(address: equal(to: internalAddresses[0]))).thenReturn(Observable.just([]))
            when(mock.getBlockHashes(address: equal(to: internalAddresses[1]))).thenReturn(Observable.just([]))
        }

        try! syncer.sync()
        verify(mockInitialSyncApi).getBlockHashes(address: equal(to: externalAddresses[0]))

        reset(mockInitialSyncApi)
        stub(mockInitialSyncApi) { mock in
            when(mock.getBlockHashes(address: equal(to: externalAddresses[0]))).thenReturn(Observable.just([]))
            when(mock.getBlockHashes(address: equal(to: externalAddresses[1]))).thenReturn(Observable.just([]))
            when(mock.getBlockHashes(address: equal(to: internalAddresses[0]))).thenReturn(Observable.just([]))
            when(mock.getBlockHashes(address: equal(to: internalAddresses[1]))).thenReturn(Observable.just([]))
        }

        try! syncer.sync()
        verify(mockInitialSyncApi).getBlockHashes(address: equal(to: externalAddresses[0]))
    }

    func testStartSyncSecondTimeAfterStopped() {
        stub(mockInitialSyncApi) { mock in
            when(mock.getBlockHashes(address: equal(to: externalAddresses[0]))).thenReturn(Observable.just([]))
            when(mock.getBlockHashes(address: equal(to: externalAddresses[1]))).thenReturn(Observable.error(ApiError.noConnection))
            when(mock.getBlockHashes(address: equal(to: internalAddresses[0]))).thenReturn(Observable.just([]))
            when(mock.getBlockHashes(address: equal(to: internalAddresses[1]))).thenReturn(Observable.just([]))
        }

        try! syncer.sync()
        verify(mockInitialSyncApi).getBlockHashes(address: equal(to: externalAddresses[0]))

        reset(mockInitialSyncApi)
        stub(mockInitialSyncApi) { mock in
            when(mock.getBlockHashes(address: equal(to: externalAddresses[0]))).thenReturn(Observable.just([]))
            when(mock.getBlockHashes(address: equal(to: externalAddresses[1]))).thenReturn(Observable.just([]))
            when(mock.getBlockHashes(address: equal(to: internalAddresses[0]))).thenReturn(Observable.just([]))
            when(mock.getBlockHashes(address: equal(to: internalAddresses[1]))).thenReturn(Observable.just([]))
        }

        try! syncer.sync()
        verify(mockInitialSyncApi).getBlockHashes(address: equal(to: externalAddresses[0]))
    }

    func testSuccessSync() {
        let thirdBlock = TestData.thirdBlock
        let secondBlock = thirdBlock.previousBlock!
        let firstBlock = secondBlock.previousBlock!
        let firstBlockHash = BlockHash(withHeaderHash: firstBlock.headerHash, height: 10)
        let secondBlockHash = BlockHash(withHeaderHash: secondBlock.headerHash, height: 12)
        let thirdBlockHash = BlockHash(withHeaderHash: thirdBlock.headerHash, height: 15)

        let externalResponse00 = BlockResponse(hash: firstBlock.reversedHeaderHashHex, height: 10)
        let externalResponse01 = BlockResponse(hash: secondBlock.reversedHeaderHashHex, height: 12)
        let internalResponse0 = BlockResponse(hash: thirdBlock.reversedHeaderHashHex, height: 15)

        stub(mockInitialSyncApi) { mock in
            when(mock.getBlockHashes(address: equal(to: externalAddresses[0]))).thenReturn(Observable.just([externalResponse00, externalResponse01]))
            when(mock.getBlockHashes(address: equal(to: externalAddresses[1]))).thenReturn(Observable.just([]))
            when(mock.getBlockHashes(address: equal(to: externalAddresses[2]))).thenReturn(Observable.just([]))
            when(mock.getBlockHashes(address: equal(to: internalAddresses[0]))).thenReturn(Observable.just([internalResponse0]))
            when(mock.getBlockHashes(address: equal(to: internalAddresses[1]))).thenReturn(Observable.just([]))
            when(mock.getBlockHashes(address: equal(to: internalAddresses[2]))).thenReturn(Observable.just([]))
            when(mock.getBlockHashes(address: equal(to: externalAddresses[5 + 0]))).thenReturn(Observable.just([]))
            when(mock.getBlockHashes(address: equal(to: externalAddresses[5 + 1]))).thenReturn(Observable.just([]))
            when(mock.getBlockHashes(address: equal(to: internalAddresses[5 + 0]))).thenReturn(Observable.just([]))
            when(mock.getBlockHashes(address: equal(to: internalAddresses[5 + 1]))).thenReturn(Observable.just([]))
        }

        stub(mockFactory) { mock in
            when(mock).blockHash(withHeaderHash: equal(to: firstBlock.headerHash), height: equal(to: externalResponse00.height)).thenReturn(firstBlockHash)
            when(mock).blockHash(withHeaderHash: equal(to: secondBlock.headerHash), height: equal(to: externalResponse01.height)).thenReturn(secondBlockHash)
            when(mock).blockHash(withHeaderHash: equal(to: thirdBlock.headerHash), height: equal(to: internalResponse0.height)).thenReturn(thirdBlockHash)
        }

        try! syncer.sync()

        XCTAssertEqual(realm.objects(BlockHash.self).count, 3)
        XCTAssertEqual(realm.objects(BlockHash.self).filter("reversedHeaderHashHex = %@", externalResponse00.hash).count, 1)
        XCTAssertEqual(realm.objects(BlockHash.self).filter("reversedHeaderHashHex = %@", externalResponse01.hash).count, 1)
        XCTAssertEqual(realm.objects(BlockHash.self).filter("reversedHeaderHashHex = %@", internalResponse0.hash).count, 1)

        verify(mockAddressManager).fillGap()
        verify(mockAddressManager).addKeys(keys: equal(to: [externalKeys[0], externalKeys[1], externalKeys[2], internalKeys[0], internalKeys[1], internalKeys[2]]))
        verify(mockAddressManager).addKeys(keys: equal(to: [externalKeys[5 + 0], externalKeys[5 + 1], internalKeys[5 + 0], internalKeys[5 + 1]]))
        verify(mockHDWallet, never()).publicKey(account: equal(to: 0), index: equal(to: 3), external: any())
        verify(mockHDWallet, never()).publicKey(account: equal(to: 1), index: equal(to: 2), external: any())

        verify(mockListener).syncStarted()
        verifyNoMoreInteractions(mockListener)
        verify(mockStateManager).restored.set(true)
        verify(mockPeerGroup).start()
    }

    func testSuccessSync_IgnoreBlocksAfterCheckpoint() {
        let secondBlock = TestData.secondBlock
        let firstBlock = secondBlock.previousBlock!
        let firstBlockHash = BlockHash(withHeaderHash: firstBlock.headerHash, height: 10)

        let externalResponse0 = BlockResponse(hash: firstBlock.reversedHeaderHashHex, height: 10)
        let externalResponse1 = BlockResponse(hash: secondBlock.reversedHeaderHashHex, height: 112)

        stub(mockInitialSyncApi) { mock in
            when(mock.getBlockHashes(address: equal(to: externalAddresses[0]))).thenReturn(Observable.just([externalResponse0]))
            when(mock.getBlockHashes(address: equal(to: externalAddresses[1]))).thenReturn(Observable.just([externalResponse1]))
            when(mock.getBlockHashes(address: equal(to: externalAddresses[2]))).thenReturn(Observable.just([]))
            when(mock.getBlockHashes(address: equal(to: externalAddresses[3]))).thenReturn(Observable.just([]))
            when(mock.getBlockHashes(address: equal(to: internalAddresses[0]))).thenReturn(Observable.just([]))
            when(mock.getBlockHashes(address: equal(to: internalAddresses[1]))).thenReturn(Observable.just([]))
            when(mock.getBlockHashes(address: equal(to: externalAddresses[5 + 0]))).thenReturn(Observable.just([]))
            when(mock.getBlockHashes(address: equal(to: externalAddresses[5 + 1]))).thenReturn(Observable.just([]))
            when(mock.getBlockHashes(address: equal(to: internalAddresses[5 + 0]))).thenReturn(Observable.just([]))
            when(mock.getBlockHashes(address: equal(to: internalAddresses[5 + 1]))).thenReturn(Observable.just([]))
        }

        stub(mockFactory) { mock in
            when(mock).blockHash(withHeaderHash: equal(to: firstBlock.headerHash), height: equal(to: externalResponse0.height)).thenReturn(firstBlockHash)
        }

        try! syncer.sync()

        XCTAssertEqual(realm.objects(BlockHash.self).count, 1)
        XCTAssertEqual(realm.objects(BlockHash.self).filter("reversedHeaderHashHex = %@", externalResponse0.hash).count, 1)

        verify(mockAddressManager).addKeys(keys: equal(to: [externalKeys[0], externalKeys[1], externalKeys[2], externalKeys[3], internalKeys[0], internalKeys[1]]))
        verify(mockHDWallet, never()).publicKey(account: equal(to: 0), index: equal(to: 4), external: equal(to: true))
        verify(mockHDWallet, never()).publicKey(account: equal(to: 0), index: equal(to: 2), external: equal(to: false))

        verify(mockStateManager).restored.set(true)
        verify(mockPeerGroup).start()
    }

    func testFailedSync_ApiError() {
        let firstBlock = TestData.firstBlock
        let firstBlockHash = BlockHash(withHeaderHash: firstBlock.headerHash, height: 10)

        let externalResponse = BlockResponse(hash: firstBlock.reversedHeaderHashHex, height: 10)

        stub(mockInitialSyncApi) { mock in
            when(mock.getBlockHashes(address: equal(to: externalAddresses[0]))).thenReturn(Observable.just([externalResponse]))
            when(mock.getBlockHashes(address: equal(to: externalAddresses[1]))).thenReturn(Observable.error(ApiError.noConnection))
            when(mock.getBlockHashes(address: equal(to: internalAddresses[0]))).thenReturn(Observable.just([]))
            when(mock.getBlockHashes(address: equal(to: internalAddresses[1]))).thenReturn(Observable.just([]))
        }

        stub(mockFactory) { mock in
            when(mock).blockHash(withHeaderHash: equal(to: firstBlock.headerHash), height: equal(to: externalResponse.height)).thenReturn(firstBlockHash)
        }

        try! syncer.sync()

        XCTAssertEqual(realm.objects(BlockHash.self).count, 0)

        verify(mockListener).syncStopped()
        verify(mockStateManager, never()).restored.set(true)
        verify(mockPeerGroup, never()).start()
    }

    func testSuccessSync_GapLimit() {
        let thirdBlock = TestData.thirdBlock
        let secondBlock = thirdBlock.previousBlock!
        let firstBlock = secondBlock.previousBlock!
        let firstBlockHash = BlockHash(withHeaderHash: firstBlock.headerHash, height: 10)
        let secondBlockHash = BlockHash(withHeaderHash: secondBlock.headerHash, height: 12)
        let thirdBlockHash = BlockHash(withHeaderHash: thirdBlock.headerHash, height: 15)

        let response1 = BlockResponse(hash: firstBlock.reversedHeaderHashHex, height: 10)
        let response2 = BlockResponse(hash: secondBlock.reversedHeaderHashHex, height: 12)
        let response3 = BlockResponse(hash: thirdBlock.reversedHeaderHashHex, height: 15)

        stub(mockInitialSyncApi) { mock in
            when(mock.getBlockHashes(address: equal(to: externalAddresses[0]))).thenReturn(Observable.just([response1, response2]))
            when(mock.getBlockHashes(address: equal(to: externalAddresses[1]))).thenReturn(Observable.just([]))
            when(mock.getBlockHashes(address: equal(to: externalAddresses[2]))).thenReturn(Observable.just([response3]))
            when(mock.getBlockHashes(address: equal(to: externalAddresses[3]))).thenReturn(Observable.just([]))
            when(mock.getBlockHashes(address: equal(to: externalAddresses[4]))).thenReturn(Observable.just([]))
            when(mock.getBlockHashes(address: equal(to: internalAddresses[0]))).thenReturn(Observable.just([]))
            when(mock.getBlockHashes(address: equal(to: internalAddresses[1]))).thenReturn(Observable.just([]))
            when(mock.getBlockHashes(address: equal(to: externalAddresses[5 + 0]))).thenReturn(Observable.just([]))
            when(mock.getBlockHashes(address: equal(to: externalAddresses[5 + 1]))).thenReturn(Observable.just([]))
            when(mock.getBlockHashes(address: equal(to: internalAddresses[5 + 0]))).thenReturn(Observable.just([]))
            when(mock.getBlockHashes(address: equal(to: internalAddresses[5 + 1]))).thenReturn(Observable.just([]))
        }

        stub(mockFactory) { mock in
            when(mock).blockHash(withHeaderHash: equal(to: firstBlock.headerHash), height: equal(to: response1.height)).thenReturn(firstBlockHash)
            when(mock).blockHash(withHeaderHash: equal(to: secondBlock.headerHash), height: equal(to: response2.height)).thenReturn(secondBlockHash)
            when(mock).blockHash(withHeaderHash: equal(to: thirdBlock.headerHash), height: equal(to: response3.height)).thenReturn(thirdBlockHash)
        }

        try! syncer.sync()

        XCTAssertEqual(realm.objects(BlockHash.self).count, 3)
        XCTAssertEqual(realm.objects(BlockHash.self).filter("reversedHeaderHashHex = %@", response1.hash).count, 1)
        XCTAssertEqual(realm.objects(BlockHash.self).filter("reversedHeaderHashHex = %@", response2.hash).count, 1)
        XCTAssertEqual(realm.objects(BlockHash.self).filter("reversedHeaderHashHex = %@", response3.hash).count, 1)

        verify(mockAddressManager).addKeys(keys: equal(to: [externalKeys[0], externalKeys[1], externalKeys[2], externalKeys[3], externalKeys[4], internalKeys[0], internalKeys[1]]))
        verify(mockHDWallet, never()).publicKey(account: equal(to: 0), index: equal(to: 5), external: equal(to: true))
        verify(mockHDWallet, never()).publicKey(account: equal(to: 0), index: equal(to: 2), external: equal(to: false))

        verify(mockStateManager).restored.set(true)
        verify(mockPeerGroup).start()
    }

}
