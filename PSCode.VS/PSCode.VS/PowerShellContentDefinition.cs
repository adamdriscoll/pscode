using Microsoft.VisualStudio.LanguageServer.Client;
using Microsoft.VisualStudio.Utilities;
using System.ComponentModel.Composition;

namespace PSCode.VS
{
    public class PowerShellContentDefinition
    {
        [Export]
        [Name("powershell")]
        [BaseDefinition(CodeRemoteContentDefinition.CodeRemoteContentTypeName)]
        internal static ContentTypeDefinition PowerShellContentTypeDefinition;

        [Export]
        [FileExtension(".ps1")]
        [ContentType("powershell")]
        internal static FileExtensionToContentTypeDefinition PowerShellFileExtensionDefinition;
    }
}
