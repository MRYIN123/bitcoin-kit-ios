import XCTest
import Cuckoo
import RealmSwift
import HSHDWalletKit
@testable import HSBitcoinKit

class PeerDelegateTests: PeerGroupTests {

    private var delegate: PeerGroup!

    override func setUp() {
        super.setUp()
        delegate = peerGroup
    }

    override func tearDown() {
        delegate = nil
        super.tearDown()
    }

    func testPeerReady() {
        let peer = peers["0"]!
        let blockHashes = [BlockHash(withHeaderHash: Data(from: 10000), height: 1)]
        let hashes = [Data(from: 111111)]
        let localKnownBestBlockHeight: Int32 = 50
        let syncPeerAnnouncedLastBlockHeight: Int32 = 100

        stub(mockBlockSyncer) { mock in
            when(mock.getBlockHashes()).thenReturn(blockHashes)
            when(mock.getBlockLocatorHashes(peerLastBlockHeight: equal(to: syncPeerAnnouncedLastBlockHeight))).thenReturn(hashes)
            when(mock.localKnownBestBlockHeight.get).thenReturn(localKnownBestBlockHeight)
        }
        stub(mockPeerManager) { mock in
            when(mock.syncPeer.get).thenReturn(peer)
        }
        stub(peer) { mock in
            when(mock.ready.get).thenReturn(true)
            when(mock.blockHashesSynced.get).thenReturn(false)
            when(mock.synced.get).thenReturn(false)
            when(mock.announcedLastBlockHeight.get).thenReturn(syncPeerAnnouncedLastBlockHeight)
        }

        delegate.peerReady(peer)
        waitForMainQueue()

        verify(peer).add(task: equal(to: GetMerkleBlocksTask(blockHashes: blockHashes)))
        verify(peer).add(task: equal(to: GetBlockHashesTask(hashes: hashes, expectedHashesMinCount: syncPeerAnnouncedLastBlockHeight - localKnownBestBlockHeight )))
        verify(mockBlockSyncer, never()).downloadCompleted()
    }

    func testPeerReady_PeerAnnouncedLastBlockHeightEqualTolocalKnownBestBlockHeight() {
        let peer = peers["0"]!
        let blockHashes = [BlockHash(withHeaderHash: Data(from: 10000), height: 1)]
        let hashes = [Data(from: 111111)]
        let localKnownBestBlockHeight: Int32 = 100
        let syncPeerAnnouncedLastBlockHeight: Int32 = 100

        stub(mockBlockSyncer) { mock in
            when(mock.getBlockHashes()).thenReturn(blockHashes)
            when(mock.getBlockLocatorHashes(peerLastBlockHeight: equal(to: syncPeerAnnouncedLastBlockHeight))).thenReturn(hashes)
            when(mock.localKnownBestBlockHeight.get).thenReturn(localKnownBestBlockHeight)
        }
        stub(mockPeerManager) { mock in
            when(mock.syncPeer.get).thenReturn(peer)
        }
        stub(peer) { mock in
            when(mock.ready.get).thenReturn(true)
            when(mock.blockHashesSynced.get).thenReturn(false)
            when(mock.synced.get).thenReturn(false)
            when(mock.announcedLastBlockHeight.get).thenReturn(syncPeerAnnouncedLastBlockHeight)
        }

        delegate.peerReady(peer)
        waitForMainQueue()

        verify(peer).add(task: equal(to: GetMerkleBlocksTask(blockHashes: blockHashes)))
        verify(peer).add(task: equal(to: GetBlockHashesTask(hashes: hashes, expectedHashesMinCount: 6 )))
        verify(mockBlockSyncer, never()).downloadCompleted()
    }

    func testPeerReady_PeerIsSyncNotPeer() {
        let peer = peers["0"]!

        stub(mockPeerManager) { mock in
            when(mock.syncPeer.get).thenReturn(nil)
        }

        delegate.peerReady(peer)
        waitForMainQueue()

        verify(peer, never()).add(task: any())
        verify(mockBlockSyncer, never()).downloadCompleted()
    }

    func testPeerReady_PeerNotReady() {
        let peer = peers["0"]!

        stub(mockPeerManager) { mock in
            when(mock.syncPeer.get).thenReturn(peer)
        }
        stub(peer) { mock in
            when(mock.ready.get).thenReturn(false)
        }

        delegate.peerReady(peer)
        waitForMainQueue()

        verify(peer, never()).add(task: any())
        verify(mockBlockSyncer, never()).downloadCompleted()
    }

    func testPeerReady_BlockHashesAlreadySynced() {
        let peer = peers["0"]!
        let blockHashes = [BlockHash(withHeaderHash: Data(from: 10000), height: 1)]

        stub(mockBlockSyncer) { mock in
            when(mock.getBlockHashes()).thenReturn(blockHashes)
            when(mock.getBlockLocatorHashes(peerLastBlockHeight: equal(to: 0))).thenReturn([])
        }
        stub(mockPeerManager) { mock in
            when(mock.syncPeer.get).thenReturn(peer)
        }
        stub(peer) { mock in
            when(mock.ready.get).thenReturn(true)
            when(mock.blockHashesSynced.get).thenReturn(true)
            when(mock.synced.get).thenReturn(false)
            when(mock.announcedLastBlockHeight.get).thenReturn(0)
        }

        delegate.peerReady(peer)
        waitForMainQueue()

        verify(peer, times(1)).add(task: any())
        verify(peer).add(task: equal(to: GetMerkleBlocksTask(blockHashes: blockHashes)))
    }

    func testPeerReady_NoBlockToDownload() {
        let peer = peers["0"]!
        let hashes = [Data(from: 111111)]

        stub(mockBlockSyncer) { mock in
            when(mock.getBlockHashes()).thenReturn([])
            when(mock.getBlockLocatorHashes(peerLastBlockHeight: equal(to: 0))).thenReturn(hashes)
        }
        stub(mockPeerManager) { mock in
            when(mock.syncPeer.get).thenReturn(peer)
        }
        stub(peer) { mock in
            when(mock.ready.get).thenReturn(true)
            when(mock.blockHashesSynced.get).thenReturn(false)
            when(mock.synced.get).thenReturn(false)
            when(mock.synced.set(any())).thenDoNothing()
            when(mock.announcedLastBlockHeight.get).thenReturn(0)
        }

        delegate.peerReady(peer)
        waitForMainQueue()

        verify(peer).synced.set(equal(to: false))
        verify(peer, times(1)).add(task: any())
        verify(peer).add(task: equal(to: GetBlockHashesTask(hashes: hashes, expectedHashesMinCount: 0)))
    }

    func testPeerReady_Synced() {
        let peer = peers["0"]!

        stub(mockBlockSyncer) { mock in
            when(mock.getBlockHashes()).thenReturn([])
            when(mock.getBlockLocatorHashes(peerLastBlockHeight: equal(to: 0))).thenReturn([])
        }
        stub(mockPeerManager) { mock in
            when(mock.syncPeer.get).thenReturn(peer)
            when(mock.syncPeer.set(any())).thenDoNothing()
        }
        stub(peer) { mock in
            when(mock.ready.get).thenReturn(true)
            when(mock.blockHashesSynced.get).thenReturn(false)
            when(mock.synced.get).thenReturn(true)
            when(mock.synced.set(any())).thenDoNothing()
            when(mock.announcedLastBlockHeight.get).thenReturn(0)
            when(mock.sendMempoolMessage()).thenDoNothing()
        }

        delegate.peerReady(peer)
        waitForMainQueue()
        waitForMainQueue()

        verify(mockBlockSyncer).downloadCompleted()
        verify(mockListener).syncFinished()
        verify(peer).sendMempoolMessage()
        verify(mockPeerManager).syncPeer.set(isNil())
    }

    func testPeerReady_Synced_AnotherPeerIsNotSynced() {
        let peer = peers["0"]!

        stub(mockBlockSyncer) { mock in
            when(mock.getBlockHashes()).thenReturn([])
            when(mock.getBlockLocatorHashes(peerLastBlockHeight: equal(to: 0))).thenReturn([])
        }
        stub(mockPeerManager) { mock in
            when(mock.syncPeer.get).thenReturn(peer)
            when(mock.syncPeer.set(any())).thenDoNothing()
        }
        stub(peer) { mock in
            when(mock.ready.get).thenReturn(true)
            when(mock.blockHashesSynced.get).thenReturn(false)
            when(mock.synced.get).thenReturn(true)
            when(mock.synced.set(any())).thenDoNothing()
            when(mock.announcedLastBlockHeight.get).thenReturn(0)
            when(mock.sendMempoolMessage()).thenDoNothing()
        }

        delegate.peerReady(peer)
        waitForMainQueue()

        verify(mockBlockSyncer).downloadCompleted()
        verify(mockListener).syncFinished()
        verify(peer).sendMempoolMessage()
        verify(mockPeerManager).syncPeer.set(isNil())

        // Here a block which sets another syncPeer is left enqueued
        let peer2 = peers["1"]!
        reset(mockPeerManager)
        stub(mockPeerManager) { mock in
            when(mock.syncPeer.get).thenReturn(nil)
            when(mock.syncPeer.set(any())).thenDoNothing()
            when(mock.nonSyncedPeer()).thenReturn(peer2)
        }

        waitForMainQueue()

        verify(mockPeerManager).syncPeer.set(equal(to: peer2, equalWhen: { $0!.host == $1!.host }))

        // Here a block which starts synchronization of newly set syncPeer is left enqueued
        waitForMainQueue()
    }

    func testPeerDidConnect() {
        let peer = peers["0"]!
        let bloomFilter = BloomFilter(elements: [Data(from: 1)])

        stub(mockBloomFilterManager) { mock in
            when(mock.bloomFilter.get).thenReturn(bloomFilter)
        }
        stub(mockPeerManager) { mock in
            when(mock.syncPeer.get).thenReturn(nil)
            when(mock.syncPeer.set(any())).thenDoNothing()
            when(mock.nonSyncedPeer()).thenReturn(peer)
            when(mock.connected()).thenReturn([peer])
            when(mock.someReadyPeers()).thenReturn([peer])
        }
        stub(peer) { mock in
            when(mock.announcedLastBlockHeight.get).thenReturn(0)
            when(mock.sendMempoolMessage()).thenDoNothing()
        }

        delegate.peerDidConnect(peer)
        waitForMainQueue()

        verify(peer).filterLoad(bloomFilter: equal(to: bloomFilter, equalWhen: { $0.filter == $1.filter }))
        verify(mockPeerManager).syncPeer.set(equal(to: peer, equalWhen: { $0!.host == $1!.host }))
        verify(mockBlockSyncer).downloadStarted()

        // Here a block which starts synchronization of newly set syncPeer is left enqueued
        stub(mockBlockSyncer) { mock in
            when(mock.getBlockHashes()).thenReturn([])
        }
        stub(mockPeerManager) { mock in
            when(mock.syncPeer.get).thenReturn(peer)
        }
        stub(peer) { mock in
            when(mock.ready.get).thenReturn(true)
            when(mock.synced.get).thenReturn(true)
            when(mock.synced.set(any())).thenDoNothing()
            when(mock.blockHashesSynced.get).thenReturn(true)
            when(mock.sendMempoolMessage()).thenDoNothing()
        }

        waitForMainQueue()

        verify(mockBlockSyncer).getBlockHashes()
        verify(mockTransactionSyncer, never()).pendingTransactions()
    }

    func testPeerDidConnect_BloomFilterIsNil() {
        let peer = peers["0"]!
        stub(mockBloomFilterManager) { mock in
            when(mock.bloomFilter.get).thenReturn(nil)
        }

        delegate.peerDidConnect(peer)
        verify(peer, never()).filterLoad(bloomFilter: any())

        waitForMainQueue()
    }

    func testPeerDidConnect_SyncPeerAlreadySet() {
        let peer = peers["0"]!

        stub(mockBloomFilterManager) { mock in
            when(mock.bloomFilter.get).thenReturn(nil)
        }
        stub(mockPeerManager) { mock in
            when(mock.syncPeer.get).thenReturn(peer)
            when(mock.connected()).thenReturn([peer])
            when(mock.someReadyPeers()).thenReturn([peer])
            when(mock.nonSyncedPeer()).thenReturn(nil)
        }

        delegate.peerDidConnect(peer)
        waitForMainQueue()
        waitForMainQueue()

        verify(mockPeerManager, never()).syncPeer.set(any())
        verify(mockBlockSyncer, never()).downloadStarted()
        verify(mockTransactionSyncer, never()).pendingTransactions()
    }

    func testPeerDidConnect_NoNonSyncPeer() {
        let peer = peers["0"]!

        stub(mockBloomFilterManager) { mock in
            when(mock.bloomFilter.get).thenReturn(nil)
        }
        stub(mockPeerManager) { mock in
            when(mock.syncPeer.get).thenReturn(nil)
            when(mock.connected()).thenReturn([peer])
            when(mock.someReadyPeers()).thenReturn([peer])
            when(mock.nonSyncedPeer()).thenReturn(nil)
        }

        delegate.peerDidConnect(peer)
        waitForMainQueue()

        verify(mockPeerManager, never()).syncPeer.set(any())
        verify(mockBlockSyncer, never()).downloadStarted()

        // Here a block which sends pending transactions is left enqueued
        stub(mockTransactionSyncer) { mock in
            when(mock.pendingTransactions()).thenReturn([])
        }

        waitForMainQueue()

        verify(mockTransactionSyncer).pendingTransactions()
    }

    func testPeerDidDisconnect_PeerIsSyncPeer() {
        peerGroup.start()
        let peer = peers["0"]!

        stub(mockReachabilityManager) { mock in
            when(mock.reachable()).thenReturn(true)
        }
        stub(mockPeerManager) { mock in
            when(mock.syncPeer.set(any())).thenDoNothing()
            when(mock.syncPeerIs(peer: any())).thenReturn(true)
            when(mock.peerDisconnected(peer: any())).thenDoNothing()
        }
        stub(mockPeerHostManager) { mock in
            when(mock.hostDisconnected(host: any(), withError: any(), networkReachable: any())).thenDoNothing()
            when(mock.peerHost.get).thenReturn(nil)
        }
        stub(mockBlockSyncer) { mock in
            when(mock.downloadFailed()).thenDoNothing()
        }


        peerGroup.peerDidDisconnect(peer, withError: nil)
        waitForMainQueue()

        verify(mockPeerHostManager).hostDisconnected(host: equal(to: peer.host), withError: isNil(), networkReachable: equal(to: true))
        verify(mockBlockSyncer).downloadFailed()
        verify(mockPeerManager).syncPeer.set(isNil())
        verify(mockPeerManager).peerDisconnected(peer: equal(to: peer, equalWhen: { $0.host == $1.host }))

        // Here two blocks are left enqueued:
        // - which sets a syncPeer
        // - which connects missing peers if exist
        let peer2 = peers["1"]!
        reset(mockPeerManager)
        stub(mockPeerManager) { mock in
            when(mock.syncPeer.get).thenReturn(nil)
            when(mock.syncPeer.set(any())).thenDoNothing()
            when(mock.nonSyncedPeer()).thenReturn(peer2)
            when(mock.totalPeersCount()).thenReturn(1)
        }


        waitForMainQueue()

        verify(mockPeerManager).syncPeer.set(equal(to: peer2, equalWhen: { $0!.host == $1!.host }))
        verify(mockPeerHostManager).peerHost.get

        // Here a block which starts synchronization of newly set syncPeer is left enqueued
        waitForMainQueue()
    }

    func testPeerDidDisconnect_PeerIsNotSyncPeer() {
        peerGroup.start()
        let peer = peers["0"]!

        stub(mockReachabilityManager) { mock in
            when(mock.reachable()).thenReturn(true)
        }
        stub(mockPeerManager) { mock in
            when(mock.syncPeerIs(peer: any())).thenReturn(false)
            when(mock.peerDisconnected(peer: any())).thenDoNothing()
        }
        stub(mockPeerHostManager) { mock in
            when(mock.hostDisconnected(host: any(), withError: any(), networkReachable: any())).thenDoNothing()
            when(mock.peerHost.get).thenReturn(nil)
        }


        peerGroup.peerDidDisconnect(peer, withError: nil)
        waitForMainQueue()

        verify(mockPeerHostManager).hostDisconnected(host: equal(to: peer.host), withError: isNil(), networkReachable: equal(to: true))
        verify(mockBlockSyncer, never()).downloadFailed()
        verify(mockPeerManager, never()).syncPeer.set(any())
        verify(mockPeerManager).peerDisconnected(peer: equal(to: peer, equalWhen: { $0.host == $1.host }))

        // Here only one block is left enqueued:
        // - which connects missing peers if exist
        stub(mockPeerManager) { mock in
            when(mock.totalPeersCount()).thenReturn(1)
        }

        waitForMainQueue()

        verify(mockPeerManager, never()).syncPeer.set(any())
        verify(mockPeerHostManager).peerHost.get

        // Here a block which starts synchronization of newly set syncPeer is left enqueued
        waitForMainQueue()
    }

    func testPeerDidDisconnect_NetworkNotReachable() {
        peerGroup.start()
        let peer = peers["0"]!

        stub(mockReachabilityManager) { mock in
            when(mock.reachable()).thenReturn(false)
        }
        stub(mockPeerManager) { mock in
            when(mock.syncPeerIs(peer: any())).thenReturn(false)
            when(mock.peerDisconnected(peer: any())).thenDoNothing()
        }
        stub(mockPeerHostManager) { mock in
            when(mock.hostDisconnected(host: any(), withError: any(), networkReachable: any())).thenDoNothing()
            when(mock.peerHost.get).thenReturn(nil)
        }

        peerGroup.peerDidDisconnect(peer, withError: nil)
        waitForMainQueue()
        waitForMainQueue()

        verify(mockPeerHostManager).hostDisconnected(host: equal(to: peer.host), withError: isNil(), networkReachable: equal(to: false))
    }

    func testPeerDidDisconnect_WithError() {
        peerGroup.start()
        let peer = peers["0"]!
        let error = PeerConnection.PeerConnectionError.connectionClosedByPeer

        stub(mockReachabilityManager) { mock in
            when(mock.reachable()).thenReturn(false)
        }
        stub(mockPeerManager) { mock in
            when(mock.syncPeerIs(peer: any())).thenReturn(false)
            when(mock.peerDisconnected(peer: any())).thenDoNothing()
        }
        stub(mockPeerHostManager) { mock in
            when(mock.hostDisconnected(host: any(), withError: any(), networkReachable: any())).thenDoNothing()
            when(mock.peerHost.get).thenReturn(nil)
        }

        peerGroup.peerDidDisconnect(peer, withError: error)
        waitForMainQueue()
        waitForMainQueue()

        verify(mockPeerHostManager).hostDisconnected(host: equal(to: peer.host), withError: equal(to: error, equalWhen: { $0! == $1! }), networkReachable: equal(to: false))
    }

    func testPeerDidCompleteTask_GetBlockHashesTask() {
        let peer = peers["0"]!
        let task = getCompleted_GetBlockHashesTask(hashes: [Data(from: 10000)])

        stub(mockBlockSyncer) { mock in
            when(mock.add(blockHashes: any())).thenDoNothing()
        }

        peerGroup.peer(peer, didCompleteTask: task)

        verify(mockBlockSyncer).add(blockHashes: equal(to: task.blockHashes))
        verify(peer, never()).blockHashesSynced.set(any())
    }

    func testPeerDidCompleteTask_GetBlockHashesTask_NoBlockHashes() {
        let peer = peers["0"]!
        let task = getCompleted_GetBlockHashesTask(hashes: [])

        stub(peer) { mock in
            when(mock.blockHashesSynced.set(any())).thenDoNothing()
        }

        peerGroup.peer(peer, didCompleteTask: task)

        verify(mockBlockSyncer, never()).add(blockHashes: any())
        verify(peer).blockHashesSynced.set(true)
    }

    func testPeerDidCompleteTask_GetMerkleBlocksTask() {
        let peer = peers["0"]!
        let blockHashes = [BlockHash(withHeaderHash: Data(from: 100000), height: 0)]
        let task = GetMerkleBlocksTask(blockHashes: blockHashes)

        stub(mockBlockSyncer) { mock in
            when(mock.downloadIterationCompleted()).thenDoNothing()
        }

        peerGroup.peer(peer, didCompleteTask: task)

        verify(mockBlockSyncer).downloadIterationCompleted()
    }

    func testPeerDidCompleteTask_RequestTransactionsTask() {
        let peer = peers["0"]!
        let transactions = [TestData.p2pkTransaction]
        let task = getCompleted_RequestTransactionsTask(transactions: transactions)

        stub(mockTransactionSyncer) { mock in
            when(mock.handle(transactions: any())).thenDoNothing()
        }

        peerGroup.peer(peer, didCompleteTask: task)

        verify(mockTransactionSyncer).handle(transactions: equal(to: task.transactions))
    }

    func testPeerDidCompleteTask_SendTransactionTask() {
        let peer = peers["0"]!
        let task = SendTransactionTask(transaction: TestData.p2pkTransaction)

        stub(mockTransactionSyncer) { mock in
            when(mock.handle(sentTransaction: any())).thenDoNothing()
        }

        peerGroup.peer(peer, didCompleteTask: task)

        verify(mockTransactionSyncer).handle(sentTransaction: equal(to: task.transaction))
    }

    func testHandleMerkleBlock() {
        let peer = peers["0"]!
        let merkleBlock = MerkleBlock(header: TestData.firstBlock.header!, transactionHashes: [], transactions: [])

        stub(peer) { mock in
            when(mock.announcedLastBlockHeight.get).thenReturn(100)
        }
        stub(mockBlockSyncer) { mock in
            when(mock.handle(merkleBlock: any(), maxBlockHeight: any())).thenDoNothing()
        }

        peerGroup.handle(peer, merkleBlock: merkleBlock)

        verify(mockBlockSyncer).handle(merkleBlock: equal(to: merkleBlock), maxBlockHeight: equal(to: 100))
        verify(peer, never()).disconnect(error: any())
    }

    func testHandleMerkleBlock_HandleWithError() {
        let peer = peers["0"]!
        let merkleBlock = MerkleBlock(header: TestData.firstBlock.header!, transactionHashes: [], transactions: [])

        stub(mockBlockSyncer) { mock in
            when(mock.handle(merkleBlock: any(), maxBlockHeight: any())).thenThrow(MerkleBlockValidator.ValidationError.notEnoughBits)
        }

        peerGroup.handle(peer, merkleBlock: merkleBlock)

        verify(mockBlockSyncer).handle(merkleBlock: equal(to: merkleBlock), maxBlockHeight: any())
        verify(peer).disconnect(error: equal(to: MerkleBlockValidator.ValidationError.notEnoughBits, equalWhen: { $0! == $1! }))
    }

    func testPeerDidReceiveAddresses() {
        let peer = peers["0"]!
        let newAddressString = "new.address.string"
        let addresses = [NetworkAddress(services: 0, address: newAddressString, port: 0)]

        stub(mockPeerHostManager) { mock in
            when(mock.addHosts(hosts: any())).thenDoNothing()
        }

        peerGroup.peer(peer, didReceiveAddresses: addresses)

        verify(mockPeerHostManager).addHosts(hosts: equal(to: [newAddressString]))
    }

    func testPeerDidReceiveInventoryItem() {
        let peer = peers["0"]!
        let blockHash = Data(from: 10000)
        let transactionHash = Data(from: 20000)
        let inventoryItems = [
            InventoryItem(type: InventoryItem.ObjectType.blockMessage.rawValue, hash: blockHash),
            InventoryItem(type: InventoryItem.ObjectType.transaction.rawValue, hash: transactionHash)
        ]

        stub(mockBlockSyncer) { mock in
            when(mock.shouldRequestBlock(withHash: any())).thenReturn(true)
        }
        stub(mockTransactionSyncer) { mock in
            when(mock.shouldRequestTransaction(hash: any())).thenReturn(true)
        }
        stub(mockPeerManager) { mock in
            when(mock.connected()).thenReturn([peer])
        }
        stub(peer) { mock in
            when(mock.isRequestingInventory(hash: any())).thenReturn(false)
            when(mock.synced.get).thenReturn(true)
            when(mock.synced.set(any())).thenDoNothing()
            when(mock.blockHashesSynced.set(any())).thenDoNothing()
        }

        peerGroup.peer(peer, didReceiveInventoryItems: inventoryItems)
        waitForMainQueue()

        verify(peer).synced.set(equal(to: false))
        verify(peer).blockHashesSynced.set(equal(to: false))
        let task = RequestTransactionsTask(hashes: [transactionHash])
        verify(peer).add(task: equal(to: task))

        // Here a block which sets another syncPeer is left enqueued
        let peer2 = peers["1"]!
        reset(mockPeerManager)
        stub(mockPeerManager) { mock in
            when(mock.syncPeer.get).thenReturn(nil)
            when(mock.syncPeer.set(any())).thenDoNothing()
            when(mock.nonSyncedPeer()).thenReturn(peer2)
        }

        waitForMainQueue()

        verify(mockPeerManager).syncPeer.set(equal(to: peer2, equalWhen: { $0!.host == $1!.host }))

        // Here a block which starts synchronization of newly set syncPeer is left enqueued
        waitForMainQueue()
    }

    func testPeerDidReceiveInventoryItem_BlockExists() {
        let peer = peers["0"]!
        let blockHash = Data(from: 10000)
        let inventoryItems = [
            InventoryItem(type: InventoryItem.ObjectType.blockMessage.rawValue, hash: blockHash)
        ]

        stub(mockBlockSyncer) { mock in
            when(mock.shouldRequestBlock(withHash: any())).thenReturn(false)
        }

        peerGroup.peer(peer, didReceiveInventoryItems: inventoryItems)
        waitForMainQueue()

        verify(peer, never()).synced.set(equal(to: false))
        verify(peer, never()).blockHashesSynced.set(equal(to: false))
        verify(mockPeerManager, never()).syncPeer.set(any())
    }

    func testPeerDidReceiveInventoryItem_TransactionExists() {
        let peer = peers["0"]!
        let transactionHash = Data(from: 20000)
        let inventoryItems = [
            InventoryItem(type: InventoryItem.ObjectType.transaction.rawValue, hash: transactionHash)
        ]

        stub(mockTransactionSyncer) { mock in
            when(mock.shouldRequestTransaction(hash: any())).thenReturn(false)
        }
        stub(mockPeerManager) { mock in
            when(mock.connected()).thenReturn([peer])
        }
        stub(peer) { mock in
            when(mock.isRequestingInventory(hash: any())).thenReturn(false)
        }

        peerGroup.peer(peer, didReceiveInventoryItems: inventoryItems)
        waitForMainQueue()

        verify(peer, never()).add(task: any())
    }

    func testPeerDidReceiveInventoryItem_TransactionAlreadyRequesting() {
        let peer = peers["0"]!
        let transactionHash = Data(from: 20000)
        let inventoryItems = [
            InventoryItem(type: InventoryItem.ObjectType.transaction.rawValue, hash: transactionHash)
        ]

        stub(mockTransactionSyncer) { mock in
            when(mock.shouldRequestTransaction(hash: any())).thenReturn(true)
        }
        stub(mockPeerManager) { mock in
            when(mock.connected()).thenReturn([peer])
        }
        stub(peer) { mock in
            when(mock.isRequestingInventory(hash: any())).thenReturn(true)
        }

        peerGroup.peer(peer, didReceiveInventoryItems: inventoryItems)
        waitForMainQueue()

        verify(peer, never()).add(task: any())
    }









    private func getCompleted_GetBlockHashesTask(hashes: [Data]) -> GetBlockHashesTask {
        let task = GetBlockHashesTask(hashes: [], expectedHashesMinCount: 0)
        var inventoryItems = [InventoryItem]()

        for hash in hashes {
            inventoryItems.append(InventoryItem(type: InventoryItem.ObjectType.blockMessage.rawValue, hash: hash))
        }

        let _ = task.handle(items: inventoryItems)

        return task
    }

    private func getCompleted_RequestTransactionsTask(transactions: [Transaction]) -> RequestTransactionsTask {
        let task = RequestTransactionsTask(hashes: [Data(from: 10000)])

        for transaction in transactions {
            let _ = task.handle(transaction: transaction)
        }

        return task
    }

}
