# ===================================================================
# SCRIPT DI BENCHMARK: SCALABILITA' SENSORI SUI (RISPOSTA RQ2)
# ===================================================================

$PackageID = "0xfcfad732bdf785fed873742062c7031970199f3fbd044d19c2fcc41ae20f9fb1"
$GasBudget = "50000000"
$TestLoads = @(1, 5, 25, 50, 75, 100, 200)
$UpdateIterations = 10 # Numero di aggiornamenti per calcolare la media

# Indirizzi fittizi necessari per soddisfare i requisiti del contratto prima della condivisione
$Distributore = "0x42428e076c9b2d2cf6bb11a4b73e2c5a62e1267ceb679f986023baf946abe30f"
$Compratore   = "0x8a28496e41041aa9a6b603f3b02a65de9782d8ef9b6f2ebabb459c8100a14ae5"

# Definizione dei 6 tipi di sensori richiesti dal revisore
$SensorTypes = @(
    @{ Name="Temperature"; Type="Single"; Min=5; Max=25; UpdateVal=15 },
    @{ Name="Humidity"; Type="Single"; Min=0; Max=100; UpdateVal=50 },
    @{ Name="Pressure"; Type="Single"; Min=900; Max=1100; UpdateVal=1013 },
    @{ Name="AirQuality"; Type="Single"; Min=0; Max=500; UpdateVal=42 },
    @{ Name="Light"; Type="Single"; Min=0; Max=1000; UpdateVal=300 },
    @{ Name="GPS"; Type="Dual"; Min1=40; Max1=42; Min2=8; Max2=10; UpdateVal1=41; UpdateVal2=9 }
)

# Funzione per eseguire comandi, misurare tempo e stampare errori reali
function Measure-SuiCommand {
    param([string]$Command, [switch]$AsJson)
    
    $sw = [Diagnostics.Stopwatch]::StartNew()
    
    # Esegue il comando e redireziona lo standard error (2) sullo standard output (1) per catturarlo
    $output = Invoke-Expression "$Command 2>&1"
    $exitCode = $LASTEXITCODE
    $sw.Stop()
    
    if ($exitCode -ne 0) {
        Write-Host "`n!!! ERRORE SUI RESTITUITO DAL NODO !!!" -ForegroundColor Red
        Write-Host "Comando fallito: $Command" -ForegroundColor Yellow
        Write-Host "Dettagli Errore:" -ForegroundColor Red
        $output | ForEach-Object { Write-Host $_ -ForegroundColor Red }
        Write-Host "Script interrotto." -ForegroundColor Red
        exit 1
    }

    $result = @{ TimeMs = $sw.ElapsedMilliseconds; Output = $output }
    
    if ($AsJson) { 
        # Filtra i [warning] per non rompere il parser JSON
        $jsonString = ($output | Where-Object { $_ -notmatch "^\[warning\]" }) -join "`n"
        try {
            $result.Output = ($jsonString | ConvertFrom-Json)
        } catch {
            Write-Host "Impossibile parsare l'output JSON." -ForegroundColor Red
        }
    }
    
    return $result
}

# Funzione per calcolare Media e Deviazione Standard
function Get-Stats ($array) {
    $avg = ($array | Measure-Object -Average).Average
    $sum = 0
    foreach ($val in $array) { $sum += [math]::Pow($val - $avg, 2) }
    $stddev = 0
    if ($array.Count -gt 1) { $stddev = [math]::Sqrt($sum / ($array.Count - 1)) }
    return @{ Average = [math]::Round($avg, 2); StdDev = [math]::Round($stddev, 2) }
}

$ResultsCSV = @()

Write-Host "INIZIO BENCHMARK SUI SCALABILITY..." -ForegroundColor Cyan

foreach ($load in $TestLoads) {
    Write-Host "`n================================================="
    Write-Host "TESTING LOAD: $load SENSORI" -ForegroundColor Yellow
    Write-Host "================================================="

    # 1. Creazione Prodotto
    $createResult = Measure-SuiCommand "sui client call --package $PackageID --module SupplyChain --function create_product --gas-budget $GasBudget --json" -AsJson
    $filtered = @($createResult.Output.effects.created | Where-Object { $_.owner -match "AddressOwner" })
    $ProductID = [string]($filtered[0].reference.objectId)
    
    # 2. Aggiunta dei Sensori (Setup)
    Write-Host "Aggiungo $load sensori..."
    for ($i = 0; $i -lt $load; $i++) {
        $sensor = $SensorTypes[$i % 6] # Cicla tra i 6 tipi di sensori
        
        if ($sensor.Type -eq "Single") {
            $cmd = "sui client call --package $PackageID --module SupplyChain --function add_single_value_sensor --args $ProductID $($sensor.Min) $($sensor.Max) --gas-budget $GasBudget"
        } else {
            $cmd = "sui client call --package $PackageID --module SupplyChain --function add_dual_value_sensor --args $ProductID $($sensor.Min1) $($sensor.Max1) $($sensor.Min2) $($sensor.Max2) --gas-budget $GasBudget"
        }
        $null = Measure-SuiCommand $cmd
        Write-Host -NoNewline "."
        Start-Sleep -Milliseconds 500
    }
    Write-Host " Fatto!"

    # 2.5 Assegnazione Distributore e Compratore
    Write-Host "Assegno distributore e compratore..."
    $null = Measure-SuiCommand "sui client call --package $PackageID --module SupplyChain --function assign_distributor --args $ProductID $Distributore --gas-budget $GasBudget"
    Start-Sleep -Milliseconds 500
    $null = Measure-SuiCommand "sui client call --package $PackageID --module SupplyChain --function assign_buyer --args $ProductID $Compratore --gas-budget $GasBudget"
    Start-Sleep -Milliseconds 500

    # 3. Condivisione del prodotto
    Write-Host "Condivido l'oggetto..."
    $shareResult = Measure-SuiCommand "sui client call --package $PackageID --module SupplyChain --function change_to_shared --args $ProductID --gas-budget $GasBudget --json" -AsJson
    
    # Nuova logica robusta per estrarre l'ID dell'oggetto condiviso
    $createdObjects = $shareResult.Output.effects.created
    if ($createdObjects) {
        # Cerchiamo l'oggetto con owner strutturato come { "Shared": ... }
        $sharedObj = $createdObjects | Where-Object { $_.owner.Shared -ne $null }
        if (-not $sharedObj) {
            # Fallback: prende il primo creato
            $sharedObj = $createdObjects[0] 
        }
        $SharedProductID = [string]($sharedObj.reference.objectId)
    }

    if (-not $SharedProductID -or $SharedProductID -eq "") {
        Write-Host "!!! ERRORE SCRIPT: Impossibile estrarre l'ID dell'oggetto condiviso." -ForegroundColor Red
        exit 1
    }
    Write-Host "-> ID Oggetto Condiviso: $SharedProductID" -ForegroundColor DarkGray

    # 4. Fase di Update (Il vero Benchmark)
    Write-Host "Eseguo $UpdateIterations aggiornamenti per calcolare latenza e std dev..."
    $updateTimes = @()
    
    for ($j = 0; $j -lt $UpdateIterations; $j++) {
        $targetSensorId = $load - 1
        $sensor = $SensorTypes[$targetSensorId % 6]

        if ($sensor.Type -eq "Single") {
            $cmd = "sui client call --package $PackageID --module SupplyChain --function update_single_value_sensor --args $SharedProductID $targetSensorId $($sensor.UpdateVal) --gas-budget $GasBudget"
        } else {
            $cmd = "sui client call --package $PackageID --module SupplyChain --function update_dual_value_sensor --args $SharedProductID $targetSensorId $($sensor.UpdateVal1) $($sensor.UpdateVal2) --gas-budget $GasBudget"
        }
        
        $res = Measure-SuiCommand $cmd
        $updateTimes += $res.TimeMs
        Write-Host "Aggiornamento $($j+1)/$UpdateIterations completato in $($res.TimeMs) ms"
        Start-Sleep -Milliseconds 500
    }

    # 5. Statistiche
    $stats = Get-Stats $updateTimes
    Write-Host "-> Risultati per $load sensori: Media = $($stats.Average) ms | StdDev = $($stats.StdDev) ms" -ForegroundColor Green

    $ResultsCSV += [PSCustomObject]@{
        NumSensors = $load
        AvgTime_ms = $stats.Average
        StdDev_ms = $stats.StdDev
    }
}

# --- STAMPA RISULTATI FINALI ---
Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host "RISULTATI BENCHMARK DA COPIARE PER IL PAPER:" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
$ResultsCSV | Format-Table -AutoSize
$ResultsCSV | Export-Csv -Path "sui_benchmark_results.csv" -NoTypeInformation
Write-Host "Dati salvati anche in 'sui_benchmark_results.csv'"