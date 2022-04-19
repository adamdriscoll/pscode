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
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace PSCode.VS
{
    [ContentType("powershell")]
    [Export(typeof(ILanguageClient))]
    internal class PowerShellLanguageClient : ILanguageClient
    {
        public string Name => "PowerShell Language Extension";

        public IEnumerable<string> ConfigurationSections => null;

        public object InitializationOptions => null;

        public IEnumerable<string> FilesToWatch => null;

        public bool ShowNotificationOnInitializeFailed => true;

        public event AsyncEventHandler<EventArgs> StartAsync;
        public event AsyncEventHandler<EventArgs> StopAsync;

        public async Task<Connection> ActivateAsync(CancellationToken token)
        {
            var directory = Path.GetDirectoryName(GetType().Assembly.Location);
            var bundledModules = Path.Combine(directory, "PowerShellEditorServices");
            var sessionTempPath = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
            var sessionDetails = Path.Combine(sessionTempPath, "session.json");

            Directory.CreateDirectory(sessionTempPath);

            var startInfo = new ProcessStartInfo();
            startInfo.FileName = "pwsh";
            startInfo.CreateNoWindow = false;
            startInfo.WindowStyle = ProcessWindowStyle.Normal;
            startInfo.UseShellExecute = true;
            startInfo.Arguments = $"-NoExit -NoLogo -NoProfile -Command \"& '{bundledModules}/PowerShellEditorServices/Start-EditorServices.ps1' -BundledModulesPath '{bundledModules}' -LogPath '{sessionTempPath}/logs.log' -SessionDetailsPath '{sessionDetails}' -FeatureFlags @() -AdditionalModules @() -HostName 'PSCode' -HostProfileId 'myclient' -HostVersion 1.0.0 -LogLevel Diagnostic\"";

            var _pwsh = new Process();
            _pwsh.Exited += (s, e) =>
            {
                Environment.Exit(0);
            };
            _pwsh.StartInfo = startInfo;
            _pwsh.Start();

            while (!File.Exists(sessionDetails))
            {
                Thread.Sleep(100);
            }

            var sessionInfoContents = File.ReadAllText(sessionDetails);
            var sessionInfo = JsonConvert.DeserializeObject<JObject>(sessionInfoContents);

            var namedPipeName = sessionInfo["languageServicePipeName"].Value<string>();
            var name = namedPipeName.Split('\\').Last();

            var _stream = new NamedPipeClientStream(".", name, PipeDirection.InOut);
            await _stream.ConnectAsync();

            return new Connection(_stream, _stream);
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
