. $PSScriptRoot\lib.ps1
Load-Keystores
$st = S
$prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
$r = (cast logs --address $st.governor "ProposalCreated(uint256,address,address,string)" --from-block 127613000 --to-block latest --rpc-url $script:RPC --json 2>&1 | Out-String)
$ErrorActionPreference = $prev
$j = $r | ConvertFrom-Json
$count = if ($null -eq $j) { 0 } else { ([array]$j).Count }
Log-Step "P3.13" "ProposalCreated re-read with the REAL signature (uint256,address,address,string)" "exactly 1 - the day-1 proposal" "found=$count" "-" $(if ($count -eq 1) { "PASS" } else { "DEVIATION" })
Log-Note "Diagnosis of P3.2, which side is wrong: the EXPECTATION. initialize() and setStakingContract() write isExcludedFromFee silently (src/DaimonV2.sol:389,395,957); only the governance setter emits ExcludedFromFeeSet (:975). Deploy-time exemptions therefore produce NO events -- the monitor cannot reconstruct the initial exemption set from logs and must read the mapping state at startup, then watch the event for CHANGES. Same lesson for P3.7: the governor's ProposalCreated is the compact 4-field signature above, not the OpenZeppelin 10-field one -- the monitor must take event signatures from the deployed ABI, never from assumptions. Both are tuning data the spec asked Part 3 to produce; no code is wrong."
Write-Output "P3b COMPLETE found=$count"
