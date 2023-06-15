function New-ScriptBlockCallback
{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    param(
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [scriptblock]$Callback
    )

    # Is this type already defined?
    if (-not ( 'CallbackEventBridge' -as [type])) {
        Add-Type @' 
        using System; 

        public sealed class CallbackEventBridge { 
            public event AsyncCallback CallbackComplete = delegate { }; 

            private CallbackEventBridge() {} 

            private void CallbackInternal(IAsyncResult result) { 
                CallbackComplete(result); 
            } 

            public AsyncCallback Callback { 
                get { return new AsyncCallback(CallbackInternal); } 
            } 

            public static CallbackEventBridge Create() { 
                return new CallbackEventBridge(); 
            } 
        } 
'@
    }
    $bridge = [callbackeventbridge]::create()
    Register-ObjectEvent -InputObject $bridge -EventName callbackcomplete -Action $Callback -MessageData $args > $null
    $bridge.Callback
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add('http://+:8080/') 
$listener.Start()
Write-host 'Listening'

$StartServiceTime = Get-Date

$requestListener = {
    [cmdletbinding()]
    param($result)

    [System.Net.HttpListener]$listener = $result.AsyncState;

    $context = $listener.EndGetContext($result);
    $request = $context.Request
    $response = $context.Response

    if ($request.Url -match '/timeout$') 
    {
        $timeout = 10
        sleep $timeout
        $message = "Timeout $timeout`n`n $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n`n)"
        $response.ContentType = 'text/html'
    }
    else 
    {
        #fast response without timeout
        $message = "no timeout $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n";
        $response.ContentType = 'text/html' ;
    }

    [byte[]]$buffer = [System.Text.Encoding]::UTF8.GetBytes($message)
    $response.ContentLength64 = $buffer.length
    $output = $response.OutputStream
    $output.Write($buffer, 0, $buffer.length)
    $output.Close()

}  

$context = $listener.BeginGetContext((New-ScriptBlockCallback -Callback $requestListener), $listener)

while ($listener.IsListening)
{
    if ($context.IsCompleted -eq $true) {
        $context = $listener.BeginGetContext((New-ScriptBlockCallback -Callback $requestListener), $listener)
    }
}

$listener.Close()
Write-host 'Terminating ...'
