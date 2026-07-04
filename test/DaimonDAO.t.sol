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

// ============================================================
// Mock del vecchio contratto Daimon (replica minima per i test di migrazione)
// Usiamo l'originale fornito dall'utente, rinominato per evitare collisioni
// di nome import; per i test includiamo solo le funzioni essenziali.
// ============================================================
contract MockOldDaimon {
    string public name = "Daimon";
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => bool) public excludedFromFee;
    uint256 public taxFeeBps = 50; // 5%, simula la fee del vecchio contratto
    uint256 private _totalSupply;

    event Transfer(address indexed from, address indexed to, uint256 value);

    constructor(uint256 initialSupply, address holder) {
        _totalSupply = initialSupply;
        _balances[holder] = initialSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        return true;
    }

    function excludeFromFee(address account) external {
        excludedFromFee[account] = true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool) {
        require(_allowances[sender][msg.sender] >= amount, "allowance");
        _allowances[sender][msg.sender] -= amount;

        uint256 fee = excludedFromFee[recipient] || excludedFromFee[sender] ? 0 : (amount * taxFeeBps) / 1000;
        uint256 net = amount - fee;

        _balances[sender] -= amount;
        _balances[recipient] += net;

        emit Transfer(sender, recipient, net);
        return true;
    }
}

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
