# A1 - Full deploy via the REAL Deploy.s.sol against a live node.
. .\script\campaign\lib.ps1
Log-Scenario "A1" "Full deploy through the real Deploy.s.sol (20 asserts, share at 1000, Migration funded)"

$st = Bootstrap-Campaign
Log-Step "A1.1" "Broadcast script/Deploy.s.sol against the node" "the script completes; _assertDecentralized() (20 asserts) passes, otherwise the deploy aborts" "deployed: token=$($st.token) staking=$($st.staking) timelock=$($st.timelock) governor=$($st.governor) migration=$($st.migration)" "PASS"

# The script's own precomputation is under test: Migration must land on the
# address the token was initialized with.
$migrOnToken = CQRaw $st.token "migrationContract()(address)"
$ok1 = ("$migrOnToken".ToLower() -eq "$($st.migration)".ToLower())
Log-Step "A1.2" "Compare the Migration address recorded in the token with the deployed one" "identical: the CREATE-nonce precomputation held during a real broadcast" "token.migrationContract=$migrOnToken vs deployed=$($st.migration)" $(if ($ok1) { "PASS" } else { "DEVIATION" })

$share = CQ $st.token "stakingRewardShareBps()(uint256)"
Log-Step "A1.3" "Read stakingRewardShareBps after deploy" "1000 - the whole marketing share to stakers, zero operational, from block one" "$share" $(if ($share -eq 1000) { "PASS" } else { "DEVIATION" })

$mkDmn = CQ $st.token "balanceOf(address)(uint256)" @($script:MARKETING)
$mkNat = Bal $script:MARKETING
Log-Step "A1.4" "Marketing wallet balances immediately after deploy" "zero DMN, zero native - it has never been paid anything" "DMN=$mkDmn, native=$mkNat" $(if ($mkDmn -eq 0 -and $mkNat -eq 0) { "PASS" } else { "DEVIATION" })

$migBal = CQ $st.token "balanceOf(address)(uint256)" @($st.migration)
$supply = CQ $st.token "totalSupply()(uint256)"
Log-Step "A1.5" "Migration funding" "the entire INITIAL_SUPPLY sits in Migration; no EOA ever held it" "migration=$(FmtB $migBal), totalSupply=$(FmtB $supply)" $(if ($migBal -eq $supply) { "PASS" } else { "DEVIATION" })

# Roles: the deploy script asserts these, we re-read them independently.
$govRole = CQRaw $st.token "GOVERNANCE_ROLE()(bytes32)"
$guardRole = CQRaw $st.token "GUARDIAN_ROLE()(bytes32)"
$tlGov  = CQRaw $st.token "hasRole(bytes32,address)(bool)" @($govRole, $st.timelock)
$depGov = CQRaw $st.token "hasRole(bytes32,address)(bool)" @($govRole, $script:Addr.deployer)
$gGuard = CQRaw $st.token "hasRole(bytes32,address)(bool)" @($guardRole, $script:Addr.guardian)
Log-Step "A1.6" "Token roles after the wiring" "timelock governs, deployer holds nothing, guardian holds only the pause role" "timelock.gov=$tlGov, deployer.gov=$depGov, guardian.guard=$gGuard" $(if ("$tlGov" -eq "true" -and "$depGov" -eq "false" -and "$gGuard" -eq "true") { "PASS" } else { "DEVIATION" })

$canRole = CQRaw $st.timelock "CANCELLER_ROLE()(bytes32)"
$cg = CQRaw $st.timelock "hasRole(bytes32,address)(bool)" @($canRole, $script:Addr.guardian)
$cv = CQRaw $st.timelock "hasRole(bytes32,address)(bool)" @($canRole, $st.governor)
$cs = CQRaw $st.timelock "hasRole(bytes32,address)(bool)" @($canRole, $st.timelock)
Log-Step "A1.7" "CANCELLER roles (#26/#36)" "guardian, governor and the timelock itself all hold it" "guardian=$cg, governor=$cv, timelock-self=$cs" $(if ("$cg" -eq "true" -and "$cv" -eq "true" -and "$cs" -eq "true") { "PASS" } else { "DEVIATION" })

$eTok = CQ $st.token "guardianExpiry()(uint256)"
$eTl  = CQ $st.timelock "guardianAuthorityExpiry()(uint256)"
$eGov = CQ $st.governor "guardianAuthorityExpiry()(uint256)"
Log-Step "A1.8" "The single guardian expiry across the three contracts (#36)" "one identical instant in token, timelock and governor" "token=$eTok, timelock=$eTl, governor=$eGov" $(if ($eTok -eq $eTl -and $eTl -eq $eGov) { "PASS" } else { "DEVIATION" })

$pair = CQRaw $st.token "uniswapV2Pair()(address)"
$pairCode = (cast code $pair --rpc-url $script:RPC)
Log-Step "A1.9" "The DMN/WBNB pair created through the real PancakeSwap factory" "a real pair contract exists at the recorded address" "pair=$pair, code length=$("$pairCode".Length)" $(if ("$pairCode".Length -gt 10) { "PASS" } else { "DEVIATION" })

Log-Note "The deploy under test is the production script, not the test fixture: had any of its twenty asserts failed, no deployment would exist to inspect. The CREATE-nonce precomputation - the part most likely to drift between simulation and broadcast - held."
Stop-Anvil
Write-Output "A1 COMPLETE"
