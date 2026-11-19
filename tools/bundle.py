import plistlib
from pathlib import Path
root = Path(__file__).resolve().parents[1]
formats = [('txt','public.plain-text','Plain text'), ('md','net.daringfireball.markdown','Markdown source'), ('rtf','public.rtf','Rich text'), ('tex','org.tug.tex','LaTeX source'), ('json','public.json','JSON'), ('html','public.html','HTML source'), ('docx','org.openxmlformats.wordprocessingml.document','Word document'), ('py','public.python-script','Python source'), ('js','com.netscape.javascript-source','JavaScript source')]
info = dict(CFBundleIconFile='qlm.icns', CFBundleName='qlm', CFBundleDisplayName='qlm', CFBundleIdentifier='com.willtaggart.qlm', CFBundleExecutable='qlm', CFBundlePackageType='APPL', CFBundleShortVersionString=(root/'VERSION').read_text().strip(), CFBundleVersion='5', LSMinimumSystemVersion='15.0', NSPrincipalClass='NSApplication', NSHighResolutionCapable=True, NSSupportsAutomaticTermination=False, NSSupportsSuddenTermination=False, NSHumanReadableCopyright='qlm · A small space for words.')
info['CFBundleDocumentTypes'] = [dict(CFBundleTypeName=title, CFBundleTypeRole='Editor', LSHandlerRank='Alternate', NSDocumentClass='QLMDocument', LSItemContentTypes=[uti], CFBundleTypeExtensions=[ext], NSExportableTypes=[f[1] for f in formats]) for ext,uti,title in formats]
# Declare the less consistently registered source types for file dialogs.
info['UTImportedTypeDeclarations'] = [dict(UTTypeIdentifier=uti, UTTypeDescription=title, UTTypeConformsTo=['public.plain-text'], UTTypeTagSpecification={'public.filename-extension':[ext]}) for ext,uti,title in formats if ext in ('md','tex','py','js')]
info.update(plistlib.loads((root/'build/native-icon/Info.plist').read_bytes()))
(root/'build/qlm.app/Contents/Info.plist').write_bytes(plistlib.dumps(info))
