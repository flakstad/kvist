const fs = require('fs');
const os = require('os');
const path = require('path');
const testElectron = require('@vscode/test-electron');

async function main() {
  const calvaRoot = process.cwd();
  const userDataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'calva-kvist-user-'));
  try {
    const vscodeVersion = process.env.CALVA_E2E_VSCODE_VERSION || '1.135.0';
    const vscodeExecutablePath = await testElectron.downloadAndUnzipVSCode(vscodeVersion);
    await testElectron.runTests({
      vscodeExecutablePath,
      extensionDevelopmentPath: calvaRoot,
      extensionTestsPath: path.join(calvaRoot, 'out', 'extension-test', 'e2e', 'suite', 'index'),
      launchArgs: [
        path.join(calvaRoot, 'test-fixtures'),
        '--disable-workspace-trust',
        `--user-data-dir=${userDataDir}`,
      ],
      extensionTestsEnv: {
        ...process.env,
        CALVA_E2E_SUITE_FILTER: 'kvist-nrepl',
      },
    });
  } finally {
    fs.rmSync(userDataDir, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
