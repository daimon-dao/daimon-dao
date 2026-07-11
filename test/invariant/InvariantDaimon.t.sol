// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {StackDeployer} from "../base/StackDeployer.sol";
import {DaimonHandler} from "./DaimonHandler.sol";

/*
 * Invariant testing handler-based: il fuzzer martella il sistema con
 * sequenze casuali di azioni (transfer, stake, withdraw, migrate, notify,
 * claim, warp) e dopo OGNI sequenza verifica che gli invarianti reggano.
 */
contract InvariantDaimon is StackDeployer {
    DaimonHandler internal handler;
    address[] internal actors;

    function setUp() public {
        deployStack();

        actors.push(address(0xA11CE));
        actors.push(address(0xB0B));
        actors.push(address(0xCA401));

        // Ogni attore parte con vecchi token (per migrare) e un po' di DMN.
        for (uint256 i = 0; i < actors.length; i++) {
            vm.prank(deployer);
            oldToken.transfer(actors[i], 50_000_000 ether);
            fundWithDmn(actors[i], 10_000_000 ether);
        }

        handler = new DaimonHandler(token, staking, migration, oldToken, treasury, actors);

        // Trasferisce agli attori i vecchi token residui? No: restano loro.
        // Il target del fuzzing e' solo l'handler.
        targetContract(address(handler));
    }

    // --- Supply entro i limiti immutabili ---
    function invariant_SupplyWithinBounds() public view {
        uint256 s = token.totalSupply();
        assertLe(s, token.INITIAL_SUPPLY(), "supply sopra INITIAL_SUPPLY (mint!)");
        assertGe(s, token.MIN_SUPPLY(), "supply sotto il floor MIN_SUPPLY");
    }

    // --- totalVotingPower == somma dei vp dei lock attivi ---
    function invariant_VotingPowerMatchesActiveLocks() public view {
        uint256 n = staking.nextLockId();
        uint256 sum;
        for (uint256 i = 0; i < n; i++) {
            (,,,,, uint256 vpGranted, bool withdrawn) = staking.locks(i);
            if (!withdrawn) sum += vpGranted;
        }
        assertEq(staking.totalVotingPower(), sum, "totalVotingPower != somma lock attivi");
    }

    // --- Somma dei vp per-utente == totalVotingPower ---
    function invariant_PerUserVotingPowerSums() public view {
        uint256 sum;
        for (uint256 i = 0; i < actors.length; i++) {
            sum += staking.votingPower(actors[i]);
        }
        assertEq(sum, staking.totalVotingPower(), "somma vp utenti != totalVotingPower");
    }

    // --- Migrazione: DMN distribuiti == vecchi token ricevuti ---
    function invariant_MigrationConservation() public view {
        // Ogni vecchio token migrato atterra nella treasury 1:1 (il vecchio
        // token non ha reflection e la treasury parte da zero): il saldo
        // vecchi-token della treasury eguaglia esattamente totalMigrated,
        // che a sua volta e' la somma dei DMN distribuiti (claim invia
        // esattamente `amount` e incrementa totalMigrated dello stesso).
        assertEq(
            oldToken.balanceOf(treasury),
            migration.totalMigrated(),
            "vecchi token in treasury != totalMigrated"
        );
        // La migration non distribuisce MAI piu' DMN del dovuto: parte da
        // INITIAL_SUPPLY e puo' solo guadagnare reflection (mai perdere oltre
        // i claim), quindi il saldo residuo non scende sotto la quota attesa.
        assertGe(
            token.balanceOf(address(migration)),
            token.INITIAL_SUPPLY() - migration.totalMigrated(),
            "la migration ha distribuito piu' DMN del dovuto"
        );
    }

    // --- Reward: il contratto trattiene esattamente funded - claimed ---
    function invariant_StakingHoldsExactRewardBalance() public view {
        assertEq(
            address(staking).balance,
            handler.ghostBnbFunded() - handler.ghostBnbClaimed(),
            "saldo BNB staking != versato - riscosso"
        );
    }

    // --- Nessun ruolo amministrativo in mani non autorizzate ---
    function invariant_NoUnauthorizedAdminRoles() public view {
        // Solo il Timelock governa token e staking; nessun attore/deployer.
        assertTrue(token.hasRole(token.GOVERNANCE_ROLE(), address(timelock)), "timelock perde la governance");
        assertFalse(token.hasRole(token.GOVERNANCE_ROLE(), deployer), "deployer ha la governance");
        assertTrue(staking.isGovernance(address(timelock)), "timelock perde governance staking");
        assertFalse(staking.isGovernance(deployer), "deployer governa lo staking");
        assertFalse(timelock.hasRole(timelock.ADMIN_ROLE(), deployer), "deployer admin del timelock");
        assertFalse(timelock.hasRole(timelock.PROPOSER_ROLE(), deployer), "deployer proposer");
        for (uint256 i = 0; i < actors.length; i++) {
            assertFalse(token.hasRole(token.GOVERNANCE_ROLE(), actors[i]), "attore ha la governance");
            assertFalse(timelock.hasRole(timelock.ADMIN_ROLE(), actors[i]), "attore admin timelock");
            assertFalse(staking.isGovernance(actors[i]), "attore governa lo staking");
        }
    }
}
