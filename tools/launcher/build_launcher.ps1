param(
  [string]$SrcPath,
  [string]$ExePath
)
$src = Get-Content -LiteralPath $SrcPath -Raw
Add-Type -TypeDefinition $src -Language CSharp -OutputAssembly $ExePath -OutputType ConsoleApplication
