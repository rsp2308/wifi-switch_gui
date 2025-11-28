$wifi = "Wi-Fi"
$usb = "Ethernet 2"
$wifiSSID = "AARAV PG 2F 5G"

# Track state to log only on changes
$lastActive = ""
$firstRun = $true
$lastReconnectTime = [DateTime]::MinValue

function Get-Timestamp {
    return Get-Date -Format "yyyy-MM-dd HH:mm:ss"
}

function Set-Metrics($wifiMetric, $usbMetric) {
    Set-NetIPInterface -InterfaceAlias $wifi -InterfaceMetric $wifiMetric -ErrorAction SilentlyContinue
    Set-NetIPInterface -InterfaceAlias $usb -InterfaceMetric $usbMetric -ErrorAction SilentlyContinue
}

function Get-ActiveInterface {
    $route = Get-NetRoute -DestinationPrefix "0.0.0.0/0" |
             Sort-Object RouteMetric |
             Select-Object -First 1

    return $route.InterfaceAlias
}

function Is-WiFiConnected {
    $wifiStatus = netsh wlan show interfaces | Select-String "State"
    if ($wifiStatus -match "connected") {
        return $true
    }
    return $false
}

function Test-WiFiInternet {
    # Check if WiFi is connected AND has internet access
    $wifiConnected = Is-WiFiConnected
    if (-not $wifiConnected) {
        return $false
    }
    
    # Test internet connectivity via ping
    $ping = Test-Connection -ComputerName 8.8.8.8 -Count 1 -Quiet -ErrorAction SilentlyContinue
    return $ping
}

function TryReconnectWiFi {
    $timestamp = Get-Timestamp
    Write-Host "[$timestamp] Attempting to reconnect WiFi..." -ForegroundColor Yellow
    netsh wlan connect name="$wifiSSID" | Out-Null
}

# Startup message
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  WiFi Failover Monitor Started" -ForegroundColor Cyan
Write-Host "  Monitoring: $wifiSSID" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

while ($true) {

    $active = Get-ActiveInterface

    if ($active -eq $wifi) {
        # Log on first run and when switching to WiFi
        if ($firstRun) {
            $timestamp = Get-Timestamp
            Write-Host "[$timestamp] WiFi is ACTIVE - Monitoring started" -ForegroundColor Green
            $firstRun = $false
        }
        elseif ($lastActive -ne $wifi -and $lastActive -ne "") {
            $timestamp = Get-Timestamp
            Write-Host "[$timestamp] WiFi is back ONLINE" -ForegroundColor Green
        }
        Set-Metrics 1 100  # Give WiFi highest priority
        $lastActive = $wifi
    }
    elseif ($active -eq $usb) {
        # Log on first run and when switching to USB
        if ($firstRun) {
            $timestamp = Get-Timestamp
            Write-Host "[$timestamp] USB Tethering is ACTIVE - Monitoring started" -ForegroundColor Yellow
            $firstRun = $false
        }
        elseif ($lastActive -ne $usb) {
            $timestamp = Get-Timestamp
            Write-Host "[$timestamp] WiFi DOWN - Switched to USB Tethering" -ForegroundColor Red
        }
        Set-Metrics 1 100  # Keep WiFi preferred so it switches back immediately when ready
        $lastActive = $usb
        
        # Always try to reconnect WiFi, but check if it has internet before considering it ready
        $now = Get-Date
        if (($now - $lastReconnectTime).TotalSeconds -ge 10) {
            TryReconnectWiFi
            $lastReconnectTime = $now
        }
        else {
            # Silently attempt reconnection without logging
            netsh wlan connect name="$wifiSSID" | Out-Null
        }
    }
    else {
        if ($lastActive -ne "unknown") {
            $timestamp = Get-Timestamp
            Write-Host "[$timestamp] Unknown route detected - Defaulting to WiFi" -ForegroundColor Cyan
        }
        Set-Metrics 1 100  # Prefer WiFi
        $lastActive = "unknown"
    }

    Start-Sleep -Seconds 3
}
