// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {StackDeployer} from "./base/StackDeployer.sol";
import {DaimonV2} from "../src/DaimonV2.sol";
import {DaimonGovernor} from "../src/DaimonGovernor.sol";

/*
 * Giro avversariale mirato pre-freeze (ciò che aggiunge valore oltre l'audit):
 *  1. snapshot/whale: vp acquisito dopo lo snapshot non conta
 *  2. valori limite (boundary)
 *  3. incentivi perversi (teoria dei giochi sulla tokenomics)
 *  4. reflection edge + coerenza contabile al wei
 */
contract AdversarialTest is StackDeployer {
    // enum ProposalState { Pending, Active, Defeated, Succeeded, Queued, Executed, Canceled }
    uint8 constant DEFEATED = 2;
    uint8 constant SUCCEEDED = 3;
    uint8 constant EXECUTED = 5;

    function setUp() public {
        deployStack();
    }

    function _stake(address who, uint256 amount, uint256 opt) internal returns (uint256 lockId) {
        fundWithDmn(who, amount);
        vm.startPrank(who);
        token.approve(address(staking), amount);
        lockId = staking.stake(amount, opt);
        vm.stopPrank();
    }

    function _state(uint256 id) internal view returns (uint8) {
        return uint8(governor.state(id));
    }

    // ============================================================
    // AREA 1 — SNAPSHOT / WHALE
    // ============================================================

    /// vp acquisito a un timestamp STRETTAMENTE successivo allo snapshot
    /// non conta per quella proposta.
    function test_A1_vpAfterSnapshotDoesNotCount() public {
        address ally = address(0xA11);
        address whale = address(0xBAD);

        vm.warp(1_000_000);
        _stake(ally, 1_000_000 ether, 0); // vp prima della proposta, cp @1_000_000

        uint256 tSnap = 2_000_000;
        vm.warp(tSnap);
        vm.prank(ally);
        uint256 id = governor.propose(address(token), 0, "", "p"); // snapshot @2_000_000

        // whale staka DOPO, a timestamp strettamente successivo
        vm.warp(tSnap + 100);
        _stake(whale, 500_000_000 ether, 3); // enorme vp 4x, ma tardi, cp @2_000_100

        assertEq(staking.votingPowerAt(whale, tSnap), 0, "vp whale trapelato nello snapshot");
        assertGt(staking.votingPowerAt(ally, tSnap), 0, "vp ally mancante");

        // voto aperto: il whale non puo' votare, l'ally si'
        vm.warp(tSnap + governor.VOTING_DELAY());
        vm.prank(whale);
        vm.expectRevert(DaimonGovernor.InsufficientVotingPower.selector);
        governor.castVote(id, 1);

        vm.prank(ally);
        governor.castVote(id, 1); // ok
    }

    /// Nuance documentata: staking allo STESSO timestamp dello snapshot conta.
    /// Richiede però stesso blocco della creazione (i timestamp di blocco su
    /// BSC/EVM sono strettamente crescenti): chi REAGISCE a una proposta già
    /// minata è sempre in un blocco successivo → escluso. Non sfruttabile.
    function test_A1_sameTimestampStakeCounts_sameBlockOnly() public {
        address u = address(0xC0);
        _stake(u, 1000 ether, 0);
        vm.warp(block.timestamp + 1 days);
        uint256 tSnap = block.timestamp;
        vm.prank(u); // serve vp per proporre
        governor.propose(address(token), 0, "", "p");
        // stesso timestamp, "dopo" nella stessa transazione-blocco
        _stake(u, 1000 ether, 0);
        assertGt(staking.votingPowerAt(u, tSnap), 1000 ether, "same-ts stake dovrebbe contare");
    }

    // ============================================================
    // AREA 2 — VALORI LIMITE
    // ============================================================

    function test_A2_stakeOneWei() public {
        address u = address(0x11);
        _stake(u, 1, 0); // opt 0 = 1.0x
        assertEq(staking.votingPower(u), 1, "vp 1 wei errato");
    }

    /// Boundary maxTx: il tetto per singola transazione è maxTxAmount
    /// (0.5% della supply iniziale = 5B DMN). Staking di maxTxAmount esatto
    /// passa; maxTxAmount+1 in un colpo reverte. "Stakare l'intera supply"
    /// non è possibile in una sola tx (per design anti-dump), va spezzato.
    function test_A2_stakeMaxTxBoundary() public {
        uint256 mtx = token.maxTxAmount();
        address u = address(0x12);
        fundWithDmn(u, mtx + 1000); // la migration è esente da maxTx: l'utente può detenere > maxTx
        vm.startPrank(u);
        token.approve(address(staking), type(uint256).max);
        staking.stake(mtx, 3); // amount == maxTx → ok
        assertEq(staking.votingPower(u), mtx * 4000 / 1000, "vp al tetto maxTx errato");
        vm.expectRevert(DaimonV2.TransferAmountExceedsMaxTx.selector);
        staking.stake(mtx + 1, 3); // amount > maxTx → reverte
        vm.stopPrank();
    }

    function test_A2_migrationClaimZeroReverts() public {
        vm.prank(address(0x13));
        vm.expectRevert(); // ZeroAmount
        migration.claim(0);
    }

    function test_A2_migrationClaimOneWei() public {
        address u = address(0x14);
        fundWithDmn(u, 1); // claim di 1 wei tramite l'helper
        assertEq(token.balanceOf(u), 1, "claim 1 wei non 1:1");
    }

    function test_A2_burnToExactFloor_neverBelow() public {
        // Porta il dead address a detenere abbastanza da coprire tutto il
        // burnable, poi verifica che _tTotal atterri ESATTAMENTE su MIN_SUPPLY.
        uint256 burnable = token.INITIAL_SUPPLY() - token.MIN_SUPPLY();
        // manda 'burnable' al dead address (deployer non escluso da reward ma
        // ha ricevuto l'intera supply nella migration; usiamo la migration).
        vm.prank(address(migration));
        token.transfer(address(0xdEaD), burnable); // dead è escluso: riceve netto? migration esclusa da fee → nessuna fee
        // dead ora detiene ~burnable; bruciamo verso il floor
        token.burnDeadBalanceToFloor();
        assertEq(token.totalSupply(), token.MIN_SUPPLY(), "supply non atterrata sul floor esatto");
        // ulteriore burn: no-op, mai sotto il floor
        token.burnDeadBalanceToFloor();
        assertEq(token.totalSupply(), token.MIN_SUPPLY(), "supply scesa sotto il floor");
    }

    function test_A2_timelockExecute_readyMinusOne_vs_exact() public {
        // proposta che passa da sola, poi boundary del timelock all'execute
        address p = address(0x15);
        _stake(p, 2_000_000 ether, 0);
        vm.warp(block.timestamp + 1 days);

        bytes memory data = abi.encodeCall(DaimonV2.setFees, (10, 10, 20));
        vm.prank(p);
        uint256 id = governor.propose(address(token), 0, data, "setFees");

        vm.warp(block.timestamp + governor.VOTING_DELAY());
        vm.prank(p);
        governor.castVote(id, 1);
        vm.warp(block.timestamp + governor.VOTING_PERIOD() + 1);
        assertEq(_state(id), SUCCEEDED, "non Succeeded");

        governor.queue(id);
        uint256 ready = block.timestamp + timelock.getMinDelay();

        // ready - 1: TooEarly (reverte)
        vm.warp(ready - 1);
        vm.expectRevert();
        governor.execute(id);

        // ready esatto: passa
        vm.warp(ready);
        governor.execute(id);
        assertEq(_state(id), EXECUTED, "non Executed a ready esatto");
    }

    // ============================================================
    // AREA 3 — INCENTIVI PERVERSI (teoria dei giochi)
    // ============================================================

    // Scenario condiviso: proposer 8, opponent 4, folla non-votante 88.
    // Total vp = 100, quorum 10%. Il for del proposer (8) da solo NON
    // raggiunge il quorum (10).
    function _quorumScenario() internal returns (uint256 id, address opp) {
        address proposer = address(0x100);
        opp = address(0x200);
        address crowd = address(0x300);
        _stake(proposer, 8_000_000 ether, 0);
        _stake(opp, 4_000_000 ether, 0);
        _stake(crowd, 88_000_000 ether, 0); // non voterà mai
        vm.warp(block.timestamp + 1 days);
        vm.prank(proposer);
        id = governor.propose(address(token), 0, "", "quorum-game");
        vm.warp(block.timestamp + governor.VOTING_DELAY());
        vm.prank(proposer);
        governor.castVote(id, 1); // for = 8 < quorum 10
    }

    /// FIX Finding 1: l'against NON conta più nel quorum (for+abstain, come
    /// OZ). Stesso scenario (for 8% < quorum 10%, against 4%): ora votare
    /// contro NON fa raggiungere il quorum → Defeated. È il comportamento
    /// CORRETTO — l'asimmetria perversa è eliminata.
    function test_A3_againstVoteDoesNotSatisfyQuorum() public {
        (uint256 id, address opp) = _quorumScenario();
        vm.prank(opp);
        governor.castVote(id, 0); // against = 4, ESCLUSO dal quorum
        vm.warp(block.timestamp + governor.VOTING_PERIOD() + 1);
        assertEq(_state(id), DEFEATED, "against non deve piu' far raggiungere il quorum");
    }

    /// Contrappunto: tacere → identico esito (Defeated). Dopo il fix, votare
    /// contro e non votare danno lo STESSO risultato: nessun incentivo
    /// perverso a restare in silenzio invece di opporsi.
    function test_A3_silenceDeniesQuorumDefeats() public {
        (uint256 id, ) = _quorumScenario();
        vm.warp(block.timestamp + governor.VOTING_PERIOD() + 1);
        assertEq(_state(id), DEFEATED, "silenzio deve bocciare");
    }

    /// L'abstain invece conta ancora nel quorum (come OZ): il fix esclude
    /// SOLO against. for 8% + abstain 4% = 12% >= 10% → Succeeded.
    function test_A3_abstainCountsTowardQuorum() public {
        (uint256 id, address opp) = _quorumScenario();
        vm.prank(opp);
        governor.castVote(id, 2); // abstain = 4 → for+abstain = 12 >= 10
        vm.warp(block.timestamp + governor.VOTING_PERIOD() + 1);
        assertEq(_state(id), SUCCEEDED, "abstain deve contare nel quorum");
    }

    /// Il voting power NON decade: dopo la scadenza del lock resta pieno
    /// (con moltiplicatore) finché non si fa withdraw. Strategia razionale:
    /// non ritirare mai → si mantiene peso di voto + quota reward senza lock.
    function test_A3_votingPowerDoesNotDecayAfterUnlock() public {
        address u = address(0x400);
        uint256 lockId = _stake(u, 1_000_000 ether, 3); // 4x, 365 giorni
        uint256 vpBefore = staking.votingPower(u);
        assertEq(vpBefore, 1_000_000 ether * 4, "vp iniziale");
        // ben oltre la scadenza del lock
        vm.warp(block.timestamp + 400 days);
        assertEq(staking.votingPower(u), vpBefore, "vp decaduto dopo unlock (invece resta pieno)");
        // e resta pieno finche' non si ritira
        vm.prank(u);
        staking.withdraw(lockId);
        assertEq(staking.votingPower(u), 0, "vp non azzerato dopo withdraw");
    }

    // ============================================================
    // AREA 4 — REFLECTION EDGE + COERENZA AL WEI
    // ============================================================

    /// Conservazione: la somma dei saldi di tutti gli holder resta <=
    /// totalSupply e vi combacia a meno di polvere (troncamento intero),
    /// anche dopo un transfer tassato.
    function test_A4_reflectionConservation() public {
        address a = address(0x51);
        address b = address(0x52);
        fundWithDmn(a, 10_000_000 ether);

        uint256 sumBefore = _sumKnown(a, b);
        assertLe(sumBefore, token.totalSupply(), "somma > supply (prima)");
        assertLt(token.totalSupply() - sumBefore, 1000, "polvere eccessiva (prima)");

        // transfer tassato a→b (nessuno dei due escluso dalla fee)
        vm.prank(a);
        token.transfer(b, 1_000_000 ether);

        uint256 sumAfter = _sumKnown(a, b);
        assertLe(sumAfter, token.totalSupply(), "somma > supply (dopo)");
        assertLt(token.totalSupply() - sumAfter, 1000, "polvere eccessiva (dopo)");

        // il netto al destinatario e' <= 96% (4% di fee), e un holder passivo
        // (la migration) ha guadagnato reflection dall'1% di tax.
        assertGt(token.balanceOf(b), 0, "b non ha ricevuto");
    }

    /// Il dead address (unico escluso dai reward) usa il percorso _tOwned e la
    /// contabilita' resta coerente dopo un burn verso il floor.
    function test_A4_deadExcludedAccountingCoherent() public {
        vm.prank(address(migration));
        token.transfer(address(0xdEaD), 5_000_000 ether);
        uint256 deadBal = token.balanceOf(address(0xdEaD));
        assertEq(deadBal, 5_000_000 ether, "dead non riflette il netto inviato (escluso da reward)");

        uint256 supplyBefore = token.totalSupply();
        token.burnDeadBalanceToFloor();
        // ha bruciato esattamente il saldo dead (< burnable), supply scende di altrettanto
        assertEq(token.totalSupply(), supplyBefore - 5_000_000 ether, "burn dead != saldo dead");
        assertEq(token.balanceOf(address(0xdEaD)), 0, "dead non azzerato");
    }

    function _sumKnown(address a, address b) internal view returns (uint256) {
        return token.balanceOf(address(migration)) +
            token.balanceOf(address(token)) +
            token.balanceOf(address(staking)) +
            token.balanceOf(address(0xdEaD)) +
            token.balanceOf(marketingWallet) +
            token.balanceOf(a) +
            token.balanceOf(b);
    }
}
