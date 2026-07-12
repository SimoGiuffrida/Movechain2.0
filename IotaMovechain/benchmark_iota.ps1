# ===================================================================
# SCRIPT DI BENCHMARK: SCALABILITA' SENSORI IOTA
# ===================================================================

# INSERISCI QUI IL PACKAGE ID DELLA TUA PUBBLICAZIONE SU IOTA
$PackageID = "0xa9f6fad9563fcae1eebb9cb967e6699560cb31bd60071c47f2d2a58d757d6672" 
$GasBudget = "50000000"
$TestLoads = @(1, 5, 25, 50, 75, 100, 200)
$UpdateIterations = 10 # Numero di aggiornamenti per calcolare la media

# Indirizzi fittizi necessari per soddisfare i requisiti del contratto prima del cambio di stato
$Distributore = "0x42428e076c9b2d2cf6bb11a4b73e2c5a62e1267ceb679f986023baf946abe30f"
$Compratore   = "0x8a28496e41041aa9a6b603f3b02a65de9782d8ef9b6f2ebabb459c8100a14ae5"

# Definizione base per il sensore intero
$SensorMin = 5
$SensorMax = 25
$SensorUpdateVal = 15

# Funzione per eseguire comandi IOTA, misurare tempo e stampare errori
function Measure-IotaCommand {
    param([string]$Command, [switch]$AsJson)
    
    $sw = [Diagnostics.Stopwatch]::StartNew()
    
    # Esegue il comando e redireziona lo standard error (2) sullo standard output (1)
    $output = Invoke-Expression "$Command 2>&1"
    $exitCode = $LASTEXITCODE
    $sw.Stop()
    
    if ($exitCode -ne 0) {
        Write-Host "`n!!! ERRORE IOTA RESTITUITO DAL NODO !!!" -ForegroundColor Red
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

Write-Host "INIZIO BENCHMARK IOTA SCALABILITY..." -ForegroundColor Cyan

foreach ($load in $TestLoads) {
    Write-Host "`n================================================="
    Write-Host "TESTING LOAD: $load SENSORI" -ForegroundColor Yellow
    Write-Host "================================================="

    # 1. Creazione Prodotto
    $createResult = Measure-IotaCommand "./iota/iota client call --package $PackageID --module SupplyChain --function create_product --gas-budget $GasBudget --json" -AsJson
    $filtered = @($createResult.Output.effects.created | Where-Object { $_.owner -match "AddressOwner" })
    $ProductID = [string]($filtered[0].reference.objectId)
    
    # 2. Aggiunta dei Sensori
    Write-Host "Aggiungo $load sensori..."
    for ($i = 0; $i -lt $load; $i++) {
        $cmd = "./iota/iota client call --package $PackageID --module SupplyChain --function add_integer_sensor --args $ProductID $SensorMin $SensorMax --gas-budget $GasBudget"
        $null = Measure-IotaCommand $cmd
        Write-Host -NoNewline "."
        Start-Sleep -Milliseconds 500
    }
    Write-Host " Fatto!"

    # 2.5 Assegnazione Distributore e Compratore
    Write-Host "Assegno distributore e compratore..."
    $null = Measure-IotaCommand "./iota/iota client call --package $PackageID --module SupplyChain --function assign_distributor --args $ProductID $Distributore --gas-budget $GasBudget"
    Start-Sleep -Milliseconds 500
    $null = Measure-IotaCommand "./iota/iota client call --package $PackageID --module SupplyChain --function assign_buyer --args $ProductID $Compratore --gas-budget $GasBudget"
    Start-Sleep -Milliseconds 500

    # 3. Cambio di stato in Shared
    Write-Host "Modifico lo stato dell'oggetto in SHARED..."
    $null = Measure-IotaCommand "./iota/iota client call --package $PackageID --module SupplyChain --function change_to_shared --args $ProductID --gas-budget $GasBudget"
    Write-Host "-> ID Oggetto: $ProductID" -ForegroundColor DarkGray

    # 3.5 Recupero l'ID (address) dell'ultimo sensore inserito dal momento che la funzione update richiede l'address
    Write-Host "Recupero l'ID dell'ultimo sensore per gli aggiornamenti..."
    $objResult = Measure-IotaCommand "./iota/iota client object $ProductID --json" -AsJson
    
    # Navigazione JSON (il path potrebbe variare leggermente in base alla versione della CLI IOTA)
    $sensorsList = $objResult.Output.content.fields.sensors
    $targetSensorAddress = [string]($sensorsList[-1].fields.id.id)
    Write-Host "-> Address sensore target: $targetSensorAddress" -ForegroundColor DarkGray

    # 4. Fase di Update (Il vero Benchmark)
    Write-Host "Eseguo $UpdateIterations aggiornamenti per calcolare latenza e std dev..."
    $updateTimes = @()
    
    for ($j = 0; $j -lt $UpdateIterations; $j++) {
        $cmd = "./iota/iota client call --package $PackageID --module SupplyChain --function update_sensor_data --args $ProductID $targetSensorAddress $SensorUpdateVal --gas-budget $GasBudget"
        
        $res = Measure-IotaCommand $cmd
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
$ResultsCSV | Export-Csv -Path "iota_benchmark_results.csv" -NoTypeInformation
Write-Host "Dati salvati anche in 'iota_benchmark_results.csv'"