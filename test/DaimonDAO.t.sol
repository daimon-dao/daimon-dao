// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/*
 * Suite di test in stile Foundry (forge-std).
 *
 * COME ESEGUIRLI (in locale, dove hai accesso di rete):
 *   1. forge init daimon-dao --no-commit   (oppure usa una cartella esistente)
 *   2. Copia tutti i file di /contracts dentro src/
 *   3. forge install foundry-rs/forge-std
 *   4. Copia questo file dentro test/
 *   5. forge test -vvv
 *
 * Non sono riuscito a eseguire questi test in questa sessione: l'ambiente
 * sandbox non ha accesso di rete per scaricare Foundry/forge-std/npm. Il
 * codice e' scritto e controllato a mano con la massima attenzione, ma
 * NON e' stato verificato da un compilatore reale in questa sessione.
 * Eseguili tu in locale e segnalami eventuali errori di compilazione: li
 * correggo immediatamente.
 */

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/DaimonV2.sol";
import "../src/DaimonStaking.sol";
import "../src/DaimonGovernor.sol";
import "../src/DaimonTimelock.sol";
import "../src/DaimonMigration.sol";
import "../src/mocks/MockUniswap.sol";
// Mock del vecchio contratto Daimon: condiviso con lo script di deploy
// testnet (script/Deploy.s.sol), vive in src/mocks.
import {MockOldDaimon} from "../src/mocks/MockOldDaimon.sol";

contract DaimonDAOTest is Test {
    DaimonV2 public tokenImpl;
    DaimonV2 public token; // proxy castato come DaimonV2
    DaimonStaking public staking;
    DaimonGovernor public governor;
    DaimonTimelock public timelock;
    DaimonMigration public migration;
    MockOldDaimon public oldToken;

    MockUniswapV2Factory public factory;
    MockUniswapV2Router02 public router;
    MockWETH public weth;

    address public deployer = address(0x1);
    address public guardian = address(0x2);
    address public marketingWallet = address(0x3);
    address public treasury = address(0x4);
    address public alice = address(0x10);
    address public bob = address(0x11);

    uint256 public constant OLD_SUPPLY = 1_000_000_000 * 1e18;

    // NOTA: dato il deploy multi-contratto con dipendenze circolari
    // (token/staking/governor/timelock/migration si riferiscono a vicenda),
    // il setup completo e' fatto in _deployFullStack(), chiamato
    // esplicitamente al primo rigo di ogni test (pattern piu' leggibile di
    // un setUp() opaco quando i contratti sono cosi' interdipendenti).

    function _deployFullStack() internal {
        vm.startPrank(deployer);

        weth = new MockWETH();
        factory = new MockUniswapV2Factory();
        router = new MockUniswapV2Router02(address(factory), address(weth));
        vm.deal(address(router), 1000 ether); // liquidita' ETH per i mock swap

        oldToken = new MockOldDaimon(OLD_SUPPLY, alice); // alice parte con tutta la vecchia supply

        // 1. Deploy implementation + proxy del token. Usiamo deployer come
        // "migrationContract" temporaneo per ricevere la initial supply: e'
        // un semplice EOA di passaggio, che subito dopo trasferira' tutto
        // alla vera DaimonMigration una volta deployata (gia' a riga ~170).
        tokenImpl = new DaimonV2();

        bytes memory initData = abi.encodeWithSelector(
            DaimonV2.initialize.selector,
            "Daimon",
            "DMN",
            deployer,           // migrationContract temporaneo = deployer stesso
            address(router),
            deployer,           // governance temporanea
            guardian,
            marketingWallet
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(tokenImpl), initData);
        token = DaimonV2(payable(address(proxy)));

        // 2. Deploy staking (usa deployer come governance temporanea)
        staking = new DaimonStaking(address(token), deployer);

        // 3. Deploy timelock: proposer/executor/canceller settati dopo aver
        // il governor (bootstrap), per ora deployer ha tutti i ruoli admin
        timelock = new DaimonTimelock(7 days, deployer, deployer, guardian, deployer);

        // 4. Deploy governor (quorum 10% = 1000 bps su 10000)
        governor = new DaimonGovernor(address(staking), address(timelock), guardian, 1000, 1000 * 1e18);

        // 5. Wiring dei ruoli del Timelock: il Governor deve essere sia
        // PROPOSER (per queue) sia EXECUTOR (execute() del Governor chiama
        // timelock.execute() con msg.sender = governor).
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(governor));
        timelock.revokeRole(timelock.PROPOSER_ROLE(), deployer);

        staking.setGovernance(address(timelock), true);
        staking.setGovernance(deployer, false);

        token.setStakingContract(address(staking)); // chiamata mentre deployer ha ancora GOVERNANCE_ROLE

        // 6. Deploy migration e trasferimento dell'intera initial supply,
        // che il token aveva accreditato a "deployer" come migrationContract
        // temporaneo in fase di initialize(). Va fatto PRIMA di cedere la
        // GOVERNANCE_ROLE al timelock: la vera DaimonMigration deve essere
        // esclusa dalle fee (in produzione lo e' automaticamente, perche' e'
        // lei il _migrationContract passato a initialize()); qui il ruolo
        // era stato ricoperto temporaneamente dal deployer.
        migration = new DaimonMigration(address(oldToken), address(token), treasury, address(timelock), 30 days);
        token.setExcludedFromFee(address(migration), true);

        uint256 deployerBal = token.balanceOf(deployer);
        token.transfer(address(migration), deployerBal);

        // 7. Handover finale della governance del token al Timelock.
        token.grantRole(token.GOVERNANCE_ROLE(), address(timelock));
        token.revokeRole(token.GOVERNANCE_ROLE(), deployer);

        // 8. Il deployer rinuncia all'ADMIN_ROLE bootstrap del Timelock:
        // da qui in poi il timelock amministra solo se stesso (le rotazioni
        // di ruolo passano da proposte di governance).
        timelock.renounceRole(timelock.ADMIN_ROLE(), deployer);

        vm.stopPrank();
    }

    // ============================================================
    // Test 1: deploy e parametri base del token
    // ============================================================
    function test_TokenInitialSupplyAndFloor() public {
        _deployFullStack();
        assertEq(token.totalSupply(), tokenImpl.INITIAL_SUPPLY());
        assertEq(token.MIN_SUPPLY(), 21_000_000_000 * 1e18);
        assertTrue(token.totalSupply() > token.MIN_SUPPLY());
    }

    function test_TokenHasNoMintFunction() public {
        // Verifica diretta: il selettore di una eventuale funzione mint(address,uint256)
        // non esiste nel contratto. Una chiamata raw a quel selettore deve
        // fallire (nessuna funzione corrispondente, nessun fallback che minti).
        _deployFullStack();
        uint256 supplyBefore = token.totalSupply();

        (bool success, ) = address(token).call(
            abi.encodeWithSignature("mint(address,uint256)", alice, 1_000_000 * 1e18)
        );
        assertFalse(success);
        assertEq(token.totalSupply(), supplyBefore);

        // Verifica anche dopo una transfer reale: la supply non sale mai.
        _giveAliceSomeNewTokens(1000 * 1e18);

        assertEq(token.totalSupply(), supplyBefore);
    }

    // ============================================================
    // Test 2: migrazione 1:1
    // ============================================================
    function test_MigrationOneToOne() public {
        _deployFullStack();

        vm.prank(alice);
        oldToken.excludeFromFee(address(treasury)); // simulazione del passaggio preparatorio nel mock

        uint256 aliceOldBalance = oldToken.balanceOf(alice);
        assertGt(aliceOldBalance, 0);

        vm.startPrank(alice);
        oldToken.approve(address(migration), aliceOldBalance);
        migration.claim(aliceOldBalance);
        vm.stopPrank();

        assertEq(token.balanceOf(alice), aliceOldBalance);
        assertEq(oldToken.balanceOf(treasury), aliceOldBalance);
        assertEq(migration.totalMigrated(), aliceOldBalance);
    }

    function test_MigrationRevertsOnFeeMismatch() public {
        _deployFullStack();
        // NON chiamiamo excludeFromFee(treasury): il mock applichera' la
        // fee del 5%, causando un mismatch che deve far revertire claim().
        uint256 aliceOldBalance = oldToken.balanceOf(alice);

        vm.startPrank(alice);
        oldToken.approve(address(migration), aliceOldBalance);
        vm.expectRevert(DaimonMigration.AmountMismatch.selector);
        migration.claim(aliceOldBalance);
        vm.stopPrank();
    }

    function test_MigrationSweepOnlyAfterDeadlineAndOnlyGovernance() public {
        _deployFullStack();

        vm.expectRevert(DaimonMigration.MigrationStillOpen.selector);
        vm.prank(address(timelock));
        migration.sweepUnclaimed();

        vm.warp(block.timestamp + 31 days);

        vm.expectRevert(DaimonMigration.OnlyGovernance.selector);
        vm.prank(alice);
        migration.sweepUnclaimed();

        vm.prank(address(timelock));
        migration.sweepUnclaimed();
    }

    // ============================================================
    // Test 3: staking e voting power vote-escrow
    // ============================================================
    function test_StakingGrantsWeightedVotingPower() public {
        _deployFullStack();
        _giveAliceSomeNewTokens(1000 * 1e18);

        vm.startPrank(alice);
        token.approve(address(staking), 1000 * 1e18);
        staking.stake(1000 * 1e18, 0); // lockOption 0 = 30gg, 1.0x
        vm.stopPrank();

        assertEq(staking.votingPower(alice), 1000 * 1e18); // 1.0x

        _giveAliceSomeNewTokens(500 * 1e18);
        vm.startPrank(alice);
        token.approve(address(staking), 500 * 1e18);
        staking.stake(500 * 1e18, 3); // lockOption 3 = 365gg, 4.0x
        vm.stopPrank();

        assertEq(staking.votingPower(alice), 1000 * 1e18 + 2000 * 1e18); // 500*4 = 2000
    }

    function test_CannotWithdrawBeforeLockEnds() public {
        _deployFullStack();
        _giveAliceSomeNewTokens(1000 * 1e18);

        vm.startPrank(alice);
        token.approve(address(staking), 1000 * 1e18);
        uint256 lockId = staking.stake(1000 * 1e18, 1); // 90gg

        vm.expectRevert(DaimonStaking.LockStillActive.selector);
        staking.withdraw(lockId);
        vm.stopPrank();

        vm.warp(block.timestamp + 91 days);
        vm.prank(alice);
        staking.withdraw(lockId);

        assertEq(staking.votingPower(alice), 0);
        assertEq(token.balanceOf(alice), 1000 * 1e18);
    }

    // ============================================================
    // Test 4: ciclo completo di governance (propose -> vote -> queue -> execute)
    // ============================================================
    function test_FullGovernanceCycle_ChangeFees() public {
        _deployFullStack();

        _giveAliceSomeNewTokens(2_000_000 * 1e18);
        vm.startPrank(alice);
        token.approve(address(staking), 2_000_000 * 1e18);
        staking.stake(2_000_000 * 1e18, 3); // lock lungo, voting power alto
        vm.stopPrank();

        bytes memory data = abi.encodeWithSelector(DaimonV2.setFees.selector, uint256(10), uint256(10), uint256(20));

        vm.prank(alice);
        uint256 proposalId = governor.propose(address(token), 0, data, "Reduce fees");

        vm.warp(block.timestamp + governor.VOTING_DELAY() + 1);

        vm.prank(alice);
        governor.castVote(proposalId, 1); // for

        vm.warp(block.timestamp + governor.VOTING_PERIOD() + 1);

        assertEq(uint8(governor.state(proposalId)), uint8(DaimonGovernor.ProposalState.Succeeded));

        governor.queue(proposalId);

        vm.warp(block.timestamp + timelock.getMinDelay() + 1); // 7 giorni + 1 secondo

        governor.execute(proposalId);

        assertEq(token.taxFee(), 10);
        assertEq(token.buybackFee(), 10);
        assertEq(token.marketingFee(), 20);
    }

    function test_ProposalDefeatedIfQuorumNotMet() public {
        _deployFullStack();

        // Il quorum e' il 10% di totalVotingPower: perche' NON venga
        // raggiunto serve molto voting power che resta a guardare. Bob
        // stake-a in massa e non vota; alice stake-a il minimo necessario
        // per proporre (proposalThreshold) e vota da sola: i suoi voti
        // restano sotto il 10% del totale.
        _giveAliceSomeNewTokens(200_000 * 1e18);

        vm.prank(alice);
        token.transfer(bob, 100_000 * 1e18); // transfer con fee 5%: bob riceve ~95k

        vm.startPrank(bob);
        token.approve(address(staking), 90_000 * 1e18);
        staking.stake(90_000 * 1e18, 0); // vp bob = 90_000e18, non votera'
        vm.stopPrank();

        vm.startPrank(alice);
        token.approve(address(staking), 1000 * 1e18);
        staking.stake(1000 * 1e18, 0); // vp alice = 1000e18 = proposalThreshold
        vm.stopPrank();

        bytes memory data = abi.encodeWithSelector(DaimonV2.setFees.selector, uint256(0), uint256(0), uint256(0));

        vm.prank(alice);
        uint256 proposalId = governor.propose(address(token), 0, data, "Zero fees");

        vm.warp(block.timestamp + governor.VOTING_DELAY() + 1);
        vm.prank(alice);
        governor.castVote(proposalId, 1);

        vm.warp(block.timestamp + governor.VOTING_PERIOD() + 1);

        // totalVotes = 1000e18 < quorum = 10% di 91_000e18 = 9_100e18
        assertEq(uint8(governor.state(proposalId)), uint8(DaimonGovernor.ProposalState.Defeated));
    }

    function test_QuorumUsesSnapshotNotLiveVotingPower() public {
        _deployFullStack();

        _giveAliceSomeNewTokens(500_000 * 1e18);
        vm.prank(alice);
        token.transfer(bob, 200_000 * 1e18); // fee 5%: bob riceve ~190k

        // Snapshot: al momento della proposta l'unico voting power e' quello
        // di alice (5000e18). Lei vota con il 100% dello snapshot: quorum
        // ampiamente raggiunto rispetto allo snapshot.
        vm.startPrank(alice);
        token.approve(address(staking), 5000 * 1e18);
        staking.stake(5000 * 1e18, 0);
        vm.stopPrank();

        bytes memory data = abi.encodeWithSelector(DaimonV2.setFees.selector, uint256(10), uint256(10), uint256(20));
        vm.prank(alice);
        uint256 proposalId = governor.propose(address(token), 0, data, "Snapshot quorum");

        vm.warp(block.timestamp + governor.VOTING_DELAY() + 1);
        vm.prank(alice);
        governor.castVote(proposalId, 1);

        vm.warp(block.timestamp + governor.VOTING_PERIOD() + 1);
        assertEq(uint8(governor.state(proposalId)), uint8(DaimonGovernor.ProposalState.Succeeded));

        // DOPO la fine del voto bob stake-a una quantita' enorme: il
        // totalVotingPower live sale a ~185_000e18, il cui 10% (18_500e18)
        // sarebbe sopra i 5000e18 votati. Se il quorum usasse il valore
        // live la proposta diventerebbe retroattivamente Defeated; con lo
        // snapshot resta Succeeded.
        vm.startPrank(bob);
        token.approve(address(staking), 180_000 * 1e18);
        staking.stake(180_000 * 1e18, 0);
        vm.stopPrank();

        assertGt(staking.totalVotingPower(), 100_000 * 1e18); // il live e' davvero cresciuto
        assertEq(uint8(governor.state(proposalId)), uint8(DaimonGovernor.ProposalState.Succeeded));
    }

    function test_ExecuteRevertsIfNotQueued() public {
        _deployFullStack();

        _giveAliceSomeNewTokens(2_000_000 * 1e18);
        vm.startPrank(alice);
        token.approve(address(staking), 2_000_000 * 1e18);
        staking.stake(2_000_000 * 1e18, 3);
        vm.stopPrank();

        bytes memory data = abi.encodeWithSelector(DaimonV2.setFees.selector, uint256(10), uint256(10), uint256(20));
        vm.prank(alice);
        uint256 proposalId = governor.propose(address(token), 0, data, "Skip the queue");

        vm.warp(block.timestamp + governor.VOTING_DELAY() + 1);
        vm.prank(alice);
        governor.castVote(proposalId, 1);

        vm.warp(block.timestamp + governor.VOTING_PERIOD() + 1);
        assertEq(uint8(governor.state(proposalId)), uint8(DaimonGovernor.ProposalState.Succeeded));

        // Proposta approvata ma MAI schedulata sul Timelock: execute() deve
        // rifiutarla, altrimenti salterebbe il delay pubblico di 7 giorni.
        vm.expectRevert(DaimonGovernor.ProposalNotQueued.selector);
        governor.execute(proposalId);

        // Percorso corretto: queue -> attesa del delay -> execute.
        governor.queue(proposalId);
        vm.warp(block.timestamp + timelock.getMinDelay() + 1);
        governor.execute(proposalId);
        assertEq(token.taxFee(), 10);
    }

    // ============================================================
    // Test 5: floor di burn mai violato
    // ============================================================
    function test_BurnNeverGoesBelowFloor() public {
        _deployFullStack();

        // Diamo al router mock una grande quantita' di token DaimonV2, cosi'
        // che swapExactETHForTokensSupportingFeeOnTransferTokens possa
        // davvero inviarli al dead address (il mock fa una transfer reale,
        // non mintata: deve avere il saldo).
        vm.prank(address(migration));
        token.transfer(address(router), 800_000_000_000 * 1e18);

        // Mandiamo ETH al token e attiviamo manualmente piu' round di
        // acquisto/burn chiamando ripetutamente la funzione pubblica di
        // pulizia contabile, dopo aver fatto arrivare token al dead address
        // tramite swap diretti sul router (simulando cio' che avverrebbe
        // dentro _buyBackAndBurn nel normale flusso di _transfer).
        vm.deal(address(this), 0);
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(token);

        // Il dead address va letto PRIMA del vm.prank: una staticcall usata
        // come argomento consumerebbe il prank, e lo swap partirebbe dal
        // test contract (senza ETH) invece che da alice.
        address dead = token.deadAddress();

        // Eseguiamo molti round di "acquisto e burn" finche' la differenza
        // fra supply corrente e MIN_SUPPLY si esaurisce, verificando ad ogni
        // passo che _tTotal non scenda mai sotto il floor.
        uint256 floor = token.MIN_SUPPLY();
        for (uint256 i = 0; i < 50; i++) {
            vm.deal(alice, 10 ether);
            vm.prank(alice);
            router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: 10 ether}(
                0, path, dead, block.timestamp + 300
            );

            token.burnDeadBalanceToFloor();

            assertGe(token.totalSupply(), floor);
            if (token.totalSupply() == floor) break;
        }
    }

    // ============================================================
    // Test 6: Guardian scadenza a 36 mesi
    // ============================================================
    function test_GuardianCanPauseBeforeExpiry() public {
        _deployFullStack();
        vm.prank(guardian);
        token.setPaused(true);
        assertTrue(token.paused());

        vm.prank(guardian);
        token.setPaused(false);
        assertFalse(token.paused());
    }

    function test_GuardianCannotPauseAfter36Months() public {
        _deployFullStack();

        vm.warp(block.timestamp + 1096 days); // 36 mesi + 1 giorno

        vm.prank(guardian);
        vm.expectRevert(DaimonV2.GuardianExpired.selector);
        token.setPaused(true);
    }

    function test_TimelockCannotGoBelowMinDelay() public {
        _deployFullStack();
        vm.prank(address(timelock));
        vm.expectRevert("DaimonTimelock: below MIN_DELAY");
        timelock.updateDelay(1 days); // sotto il minimo di 7 giorni
    }

    function test_FeesCannotExceedHardCap() public {
        _deployFullStack();
        vm.prank(address(timelock));
        vm.expectRevert(DaimonV2.FeeTooHigh.selector);
        token.setFees(50, 30, 30); // 11% totale, sopra il cap del 10%
    }

    // ============================================================
    // Test 7: fix della security review
    // ============================================================

    // --- A1: castVote usa lo snapshot, non il voting power live ---
    function test_CastVoteUsesSnapshotVotingPower() public {
        _deployFullStack();
        _giveAliceSomeNewTokens(200_000 * 1e18);

        // alice staka PRIMA della proposta e passa token a bob
        vm.startPrank(alice);
        token.approve(address(staking), 2000 * 1e18);
        staking.stake(2000 * 1e18, 0);
        token.transfer(bob, 50_000 * 1e18);
        vm.stopPrank();

        bytes memory data = abi.encodeWithSelector(DaimonV2.setFees.selector, uint256(10), uint256(10), uint256(20));
        vm.prank(alice);
        uint256 proposalId = governor.propose(address(token), 0, data, "Snapshot votes");

        // bob staka DOPO la creazione della proposta (durante il voting delay)
        vm.warp(block.timestamp + 12 hours);
        vm.startPrank(bob);
        token.approve(address(staking), 40_000 * 1e18);
        staking.stake(40_000 * 1e18, 0);
        vm.stopPrank();

        vm.warp(block.timestamp + 13 hours); // oltre voteStart, dentro il periodo di voto

        // bob ha voting power live ma NON allo snapshot: non puo' votare
        assertGt(staking.votingPower(bob), 0);
        vm.prank(bob);
        vm.expectRevert(DaimonGovernor.InsufficientVotingPower.selector);
        governor.castVote(proposalId, 1);

        // alice invece vota con il peso che aveva allo snapshot
        vm.prank(alice);
        governor.castVote(proposalId, 1);
    }

    function test_VotingPowerAtTracksCheckpoints() public {
        _deployFullStack();
        _giveAliceSomeNewTokens(1000 * 1e18);

        // Timestamp fissi (letterali): con via-ir il compilatore considera
        // block.timestamp invariante nella transazione e puo' ri-leggerlo
        // dopo un vm.warp invece di riusare il valore salvato prima —
        // quindi qui non deriviamo mai i timestamp da block.timestamp.
        uint256 tStake = 1_000_000;
        vm.warp(tStake);

        vm.startPrank(alice);
        token.approve(address(staking), 1000 * 1e18);
        uint256 lockId = staking.stake(1000 * 1e18, 0); // 30gg, 1x
        vm.stopPrank();

        assertEq(staking.votingPowerAt(alice, tStake), 1000 * 1e18);
        assertEq(staking.votingPowerAt(alice, tStake - 1), 0); // prima dello stake: zero

        vm.warp(tStake + 31 days);
        vm.prank(alice);
        staking.withdraw(lockId);

        assertEq(staking.votingPowerAt(alice, tStake + 31 days), 0);          // oggi: zero
        assertEq(staking.votingPowerAt(alice, tStake + 1 days), 1000 * 1e18); // lo storico resta interrogabile
    }

    // --- A2: nessun EOA detiene l'admin del Timelock dopo il wiring ---
    function test_NoEOAHoldsTimelockAdminAfterWiring() public {
        _deployFullStack();
        bytes32 adminRole = timelock.ADMIN_ROLE();
        bytes32 proposerRole = timelock.PROPOSER_ROLE();

        assertTrue(timelock.hasRole(adminRole, address(timelock))); // self-administered
        assertFalse(timelock.hasRole(adminRole, deployer));
        assertFalse(timelock.hasRole(adminRole, guardian));
        assertFalse(timelock.hasRole(adminRole, alice));

        // il deployer non puo' piu' ruotare ruoli
        vm.prank(deployer);
        vm.expectRevert();
        timelock.grantRole(proposerRole, deployer);
    }

    // --- A3 + M1: swap fee con slippage protection e split dei fondi ---
    function test_FeeSwapSlippageProtectedAndFundsSplit() public {
        _deployFullStack();

        // abbassa la soglia di swap al minimo consentito (0.0001% = 1M token)
        vm.prank(address(timelock));
        token.setMinimumTokensBeforeSwap(1_000_000 * 1e18);

        vm.deal(address(router), 5000 ether);

        // accumula fee nel contratto: transfer con fee alice -> bob
        _giveAliceSomeNewTokens(100_000_000 * 1e18);
        vm.prank(alice);
        token.transfer(bob, 50_000_000 * 1e18); // 4% liquidity fee = 2M token al contratto

        assertGe(token.balanceOf(address(token)), 1_000_000 * 1e18);

        address pair = token.uniswapV2Pair();
        address dead = token.deadAddress();
        uint256 marketingBefore = marketingWallet.balance;

        // sell verso la pair: innesca _swapAccumulatedFees (con minOut dal
        // quote del router) e poi il buyback (anch'esso con minOut)
        vm.prank(alice);
        token.transfer(pair, 1000 * 1e18);

        // 1M token swappati a rate 1e15 = 1000 ether ricevuti:
        // ramo marketing = 20/40 = 500 ether, di cui 60% staking / 40% wallet
        assertEq(marketingWallet.balance - marketingBefore, 200 ether);
        assertEq(address(staking).balance, 300 ether);
        assertEq(staking.undistributedRewards(), 300 ether); // nessuno staka: accodati (M1)
        assertGt(token.balanceOf(dead), 0); // buyback eseguito nonostante minOut > 0
    }

    function test_MaxSwapSlippageGovernedAndBounded() public {
        _deployFullStack();
        assertEq(token.maxSwapSlippageBps(), 500); // default 5%

        vm.prank(alice);
        vm.expectRevert();
        token.setMaxSwapSlippageBps(1000); // non governance

        vm.prank(address(timelock));
        vm.expectRevert("DaimonV2: slippage out of range");
        token.setMaxSwapSlippageBps(3001);

        vm.prank(address(timelock));
        vm.expectRevert("DaimonV2: slippage out of range");
        token.setMaxSwapSlippageBps(49);

        vm.prank(address(timelock));
        token.setMaxSwapSlippageBps(1000);
        assertEq(token.maxSwapSlippageBps(), 1000);
    }

    // --- M3: withdraw sottrae esattamente il voting power accreditato ---
    function test_WithdrawUsesStoredVotingPower() public {
        _deployFullStack();
        _giveAliceSomeNewTokens(1500 * 1e18);

        vm.startPrank(alice);
        token.approve(address(staking), 1500 * 1e18);
        uint256 lockA = staking.stake(1000 * 1e18, 0); // 1x -> 1000
        uint256 lockB = staking.stake(500 * 1e18, 3);  // 4x -> 2000
        vm.stopPrank();

        assertEq(staking.votingPower(alice), 3000 * 1e18);

        vm.warp(block.timestamp + 366 days);
        vm.prank(alice);
        staking.withdraw(lockB);
        assertEq(staking.votingPower(alice), 1000 * 1e18); // esattamente -2000
        assertEq(staking.totalVotingPower(), 1000 * 1e18);

        vm.prank(alice);
        staking.withdraw(lockA);
        assertEq(staking.votingPower(alice), 0);
        assertEq(staking.totalVotingPower(), 0);
    }

    // --- M5: il dead address non matura reflection ---
    function test_DeadAddressDoesNotAccrueReflections() public {
        _deployFullStack();

        vm.prank(address(migration));
        token.transfer(address(router), 1_000_000 * 1e18);

        address dead = token.deadAddress();
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(token);

        vm.deal(alice, 1 ether);
        vm.prank(alice);
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: 1 ether}(
            0, path, dead, block.timestamp + 300
        );

        uint256 deadBal = token.balanceOf(dead);
        assertGt(deadBal, 0);

        // molte transfer con fee: le reflection non devono accrescere il dead
        _giveAliceSomeNewTokens(10_000_000 * 1e18);
        vm.startPrank(alice);
        for (uint256 i = 0; i < 5; i++) {
            token.transfer(bob, 1_000_000 * 1e18);
        }
        vm.stopPrank();

        assertEq(token.balanceOf(dead), deadBal);
    }

    // --- M1 + M2: reward accodati senza staker e distribuiti al primo notify utile ---
    function test_UndistributedRewardsFlowToFirstStaker() public {
        _deployFullStack();

        vm.deal(address(this), 10 ether);
        staking.notifyRewardAmount{value: 4 ether}(4 ether);
        assertEq(staking.undistributedRewards(), 4 ether);
        assertEq(staking.pendingReward(alice), 0);

        _giveAliceSomeNewTokens(1000 * 1e18);
        vm.startPrank(alice);
        token.approve(address(staking), 1000 * 1e18);
        staking.stake(1000 * 1e18, 0);
        vm.stopPrank();

        staking.notifyRewardAmount{value: 2 ether}(2 ether);
        assertEq(staking.undistributedRewards(), 0);
        assertEq(staking.pendingReward(alice), 6 ether); // 4 accodati + 2 nuovi, esatti con scala 1e27

        uint256 balBefore = alice.balance;
        vm.prank(alice);
        staking.claimReward();
        assertEq(alice.balance - balBefore, 6 ether);
    }

    // --- B7: dopo la scadenza il guardian puo' solo togliere la pausa ---
    function test_GuardianCanUnpauseAfterExpiry() public {
        _deployFullStack();
        vm.prank(guardian);
        token.setPaused(true);

        vm.warp(block.timestamp + 1096 days);

        vm.prank(guardian);
        vm.expectRevert(DaimonV2.GuardianExpired.selector);
        token.setPaused(true);

        vm.prank(guardian);
        token.setPaused(false);
        assertFalse(token.paused());
    }

    // --- B3: support invalido rifiutato ---
    function test_CastVoteRevertsOnInvalidSupport() public {
        _deployFullStack();
        _giveAliceSomeNewTokens(2000 * 1e18);
        vm.startPrank(alice);
        token.approve(address(staking), 2000 * 1e18);
        staking.stake(2000 * 1e18, 0);
        vm.stopPrank();

        bytes memory data = abi.encodeWithSelector(DaimonV2.setFees.selector, uint256(10), uint256(10), uint256(20));
        vm.prank(alice);
        uint256 proposalId = governor.propose(address(token), 0, data, "Invalid support");

        vm.warp(block.timestamp + governor.VOTING_DELAY() + 1);
        vm.prank(alice);
        vm.expectRevert(DaimonGovernor.InvalidSupport.selector);
        governor.castVote(proposalId, 3);
    }

    // --- B4: claim reverta se il NUOVO token applica una fee ---
    function test_MigrationRevertsIfNewTokenTakesFee() public {
        _deployFullStack();

        // errore di wiring simulato: la migration perde l'esclusione dalle fee
        vm.prank(address(timelock));
        token.setExcludedFromFee(address(migration), false);

        oldToken.excludeFromFee(treasury); // il lato del vecchio token e' a posto
        vm.startPrank(alice);
        oldToken.approve(address(migration), 1000 * 1e18);
        vm.expectRevert(DaimonMigration.AmountMismatch.selector);
        migration.claim(1000 * 1e18);
        vm.stopPrank();
    }

    // --- B6: eventi sui setter sensibili ---
    function test_SetterEventsEmitted() public {
        _deployFullStack();

        vm.prank(address(timelock));
        vm.expectEmit(true, false, false, true, address(token));
        emit DaimonV2.ExcludedFromFeeSet(alice, true);
        token.setExcludedFromFee(alice, true);

        vm.prank(address(timelock));
        vm.expectEmit(true, false, false, true, address(token));
        emit DaimonV2.MarketingWalletSet(bob);
        token.setMarketingWallet(bob);

        vm.prank(address(timelock));
        vm.expectEmit(false, false, false, true, address(token));
        emit DaimonV2.SwapAndLiquifyEnabledSet(false);
        token.setSwapAndLiquifyEnabled(false);

        vm.prank(address(timelock));
        vm.expectEmit(false, false, false, true, address(token));
        emit DaimonV2.BuyBackEnabledSet(false);
        token.setBuyBackEnabled(false);
    }

    // --- M7: floor sulla soglia di swap ---
    function test_MinimumSwapThresholdHasFloor() public {
        _deployFullStack();
        uint256 floorAmt = token.totalSupply() / 1_000_000;

        vm.prank(address(timelock));
        vm.expectRevert("DaimonV2: swap threshold too low");
        token.setMinimumTokensBeforeSwap(floorAmt - 1);

        vm.prank(address(timelock));
        token.setMinimumTokensBeforeSwap(floorAmt);
        assertEq(token.minimumTokensBeforeSwap(), floorAmt);
    }

    // ============================================================
    // Helpers
    // ============================================================
    function _giveAliceSomeNewTokens(uint256 amount) internal {
        // Per i test che non passano dalla migration, il deployer (che
        // detiene il resto della initial supply prima del transfer a
        // migration) puo' non avere piu' fondi dopo _deployFullStack.
        // Qui simuliamo un secondo canale: usiamo direttamente la migration
        // per dare ad alice dei nuovi token, presupponendo che alice abbia
        // ancora vecchi Daimon da migrare (ha l'intera OLD_SUPPLY in setUp).
        // Il passaggio preparatorio documentato in DaimonMigration (azzerare
        // la fee del vecchio token verso la treasury) e' replicato qui:
        // senza, claim() reverte con AmountMismatch per design.
        oldToken.excludeFromFee(treasury);
        vm.startPrank(alice);
        oldToken.approve(address(migration), amount);
        migration.claim(amount);
        vm.stopPrank();
    }
}
