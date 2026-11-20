param([Parameter(Mandatory=$true)][string]$Baseline,[Parameter(Mandatory=$true)][string]$Candidate)
$ErrorActionPreference='Stop'
$a=Get-Content -Raw -LiteralPath $Baseline | ConvertFrom-Json
$b=Get-Content -Raw -LiteralPath $Candidate | ConvertFrom-Json
if (-not $a.passed -or -not $b.passed) { Write-Error 'Test failure; see JSON.'; exit 2 }
if ($a.schemaVersion -ne $b.schemaVersion -or $a.fixtureVersion -ne $b.fixtureVersion) { Write-Error 'Version mismatch.'; exit 2 }
$x=@($a.tests|Sort-Object id);$y=@($b.tests|Sort-Object id)
if ($x.Count -ne $y.Count) { Write-Error 'Case count mismatch.'; exit 1 }
for($i=0;$i -lt $x.Count;$i++) {
 if ($x[$i].id -ne $y[$i].id -or $x[$i].fingerprint -ne $y[$i].fingerprint -or $x[$i].passed -ne $y[$i].passed) {
   Write-Error "Regression at case $($x[$i].id)";exit 1
 }
}
Write-Host "PASS: $($x.Count) tests have identical internal results."
exit 0
