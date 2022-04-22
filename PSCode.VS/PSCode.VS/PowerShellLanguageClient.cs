using Microsoft.VisualStudio.LanguageServer.Client;
using Microsoft.VisualStudio.Threading;
using Microsoft.VisualStudio.Utilities;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using System;
using System.Collections.Generic;
using System.ComponentModel.Composition;
using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

namespace PSCode.VS
{
    [ContentType("powershell")]
    [Export(typeof(ILanguageClient))]
    internal class PowerShellLanguageClient : ILanguageClient
    {
        public string Name => "powershell";

        public IEnumerable<string> ConfigurationSections => null;

        public object InitializationOptions => null;

        public IEnumerable<string> FilesToWatch => null;

        public bool ShowNotificationOnInitializeFailed => true;

        public event AsyncEventHandler<EventArgs> StartAsync;
        public event AsyncEventHandler<EventArgs> StopAsync;

        public async Task<Connection> ActivateAsync(CancellationToken token)
        {
            await Task.CompletedTask;

            var directory = Path.GetDirectoryName(GetType().Assembly.Location);
            var bundledModules = Path.Combine(directory, "PowerShellEditorServices");
            var sessionTempPath = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
            var sessionDetails = Path.Combine(sessionTempPath, "session.json");

            Directory.CreateDirectory(sessionTempPath);

            var startInfo = new ProcessStartInfo();
            startInfo.FileName = "pwsh";
            startInfo.UseShellExecute = true;
            startInfo.CreateNoWindow = false;
            startInfo.Arguments = $"-NoProfile -Command \"& Import-Module '{bundledModules}/PowerShellEditorServices/PowerShellEditorServices.psd1'; Start-EditorServices -BundledModulesPath '{bundledModules}' -LogPath '{sessionTempPath}/logs.log' -SessionDetailsPath '{sessionDetails}' -AdditionalModules @() -FeatureFlags @() -HostName 'PSCode' -HostProfileId 'myclient' -HostVersion 1.0.0 -LogLevel Diagnostic\"";

            var _pwsh = new Process();

            _pwsh.StartInfo = startInfo;
            _pwsh.Start();

            while (!File.Exists(sessionDetails))
            {
                Thread.Sleep(100);
            }

            var sessionDetailsText = File.ReadAllText(sessionDetails);
            var json = JsonConvert.DeserializeObject<JObject>(sessionDetailsText);
            var pipeName = json["languageServicePipeName"].Value<string>();
            pipeName = pipeName.Split('\\').Last();
            var namedPipe = new NamedPipeClientStream(".", pipeName, PipeDirection.InOut, PipeOptions.Asynchronous | PipeOptions.WriteThrough);
            await namedPipe.ConnectAsync(); 

            return new Connection(namedPipe, namedPipe);
            //return new Connection(_pwsh.StandardOutput.BaseStream, _pwsh.StandardInput.BaseStream);
        }

        public async Task OnLoadedAsync()
        {
            await StartAsync.InvokeAsync(this, EventArgs.Empty);
        }

        public Task OnServerInitializedAsync()
        {
            return Task.CompletedTask;
        }

        public async Task<InitializationFailureContext> OnServerInitializeFailedAsync(ILanguageClientInitializationInfo initializationState)
        {
            await Task.CompletedTask;
            return null;
        }
    }
}
