import * as assert from 'assert';
import * as cp from 'child_process';
import * as fs from 'fs';
import * as mocha from 'mocha';
import * as os from 'os';
import * as path from 'path';
import * as vscode from 'vscode';
import * as testUtil from './util';
import * as calvaUtil from '../../../utilities';
import * as replSession from '../../../nrepl/repl-session';
import * as outputWindow from '../../../repl-window/repl-window-doc';
import * as connectTypes from '../../../nrepl/connect-sequence-types';

suite('Kvist nREPL compatibility', () => {
  const suiteName = 'Kvist nREPL';
  let server: cp.ChildProcess;
  let testDir: string;
  let testFile: string;
  let port: string;
  let serverErr = '';
  let serverOut = '';

  mocha.before(async function () {
    this.timeout(120_000);
    const binary = process.env.KVIST_E2E_BINARY;
    const kvistRoot = process.env.KVIST_E2E_ROOT;
    assert.ok(binary, 'KVIST_E2E_BINARY must be set');
    assert.ok(kvistRoot, 'KVIST_E2E_ROOT must be set');

    testDir = await fs.promises.mkdtemp(path.join(os.tmpdir(), 'calva-kvist-'));
    testFile = path.join(testDir, 'calva-e2e.kvist');
    const portFile = path.join(testDir, '.nrepl-port');
    await fs.promises.writeFile(
      testFile,
      [
        '(package main)',
        '(def calva-loaded: int 41)',
        '(+ calva-loaded 2)',
        '(defstruct CalvaGreeting {',
        '  message: string',
        '})',
        '(defn calva-greeting-length [message: string] -> int',
        '  (count message))',
        '(defn calva-branch-output []',
        '  (println "calva-branch-output"))',
        '(calva-greeting-length "hei")',
        '(if true (calva-branch-output) (calva-branch-output))',
        '(println "calva-load-output")',
        '(+ calva-loaded 4)',
        '(comment',
        '  (+ calva-loaded 1)',
        '  (println)',
        '  (pri))',
        '',
      ].join('\n')
    );

    server = cp.spawn(binary, ['nrepl', testFile, '--port', '0', '--port-file', portFile], {
      env: { ...process.env, KVIST_ROOT: kvistRoot },
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    server.stderr?.on('data', (chunk) => (serverErr += chunk.toString()));
    server.stdout?.on('data', (chunk) => (serverOut += chunk.toString()));
    await testUtil.waitForCondition(
      async () => {
        try {
          port = (await fs.promises.readFile(portFile, 'utf8')).trim();
          return /^\d+$/.test(port);
        } catch {
          if (server.exitCode !== null) {
            throw new Error(`Kvist nREPL exited early: ${serverErr}`);
          }
          return false;
        }
      },
      30_000,
      50,
      'Kvist nREPL did not write its port file'
    );
    testUtil.log(suiteName, `Kvist server ready on ${port}`);

    await vscode.workspace
      .getConfiguration('files')
      .update('associations', { '*.kvist': 'clojure' }, vscode.ConfigurationTarget.Global);
    await vscode.workspace
      .getConfiguration('calva')
      .update('autoSelectNReplPortFromPortFile', true, vscode.ConfigurationTarget.Global);
    await vscode.workspace.getConfiguration('calva').update(
      'outputDestinations',
      {
        evalResults: 'repl-window',
        evalOutput: 'repl-window',
        otherOutput: 'repl-window',
      },
      vscode.ConfigurationTarget.Global
    );
    await vscode.commands.executeCommand('calva.activateCalva');
    const result = await vscode.commands.executeCommand<{ connected: boolean }>('calva.connect', {
      connectSequence: {
        name: 'Generic',
        projectType: connectTypes.ProjectTypes.generic,
        cljsType: connectTypes.CljsTypes.none,
        projectRootPath: [testDir],
      },
      disableAutoSelect: true,
    });
    assert.ok(result?.connected, 'Calva connect command returned disconnected');
    await testUtil.waitForCondition(
      () => calvaUtil.getConnectedState(),
      30_000,
      50,
      'Calva did not connect to the Kvist nREPL adapter'
    );
  });

  mocha.after(async () => {
    const session = replSession.getSession();
    if (session) {
      await session.client.close();
    }
    if (server?.exitCode === null) {
      server.kill('SIGTERM');
    }
  });

  test('connects and evaluates through Calva', async () => {
    const session = replSession.getSession();
    assert.ok(session, 'Expected a routed Calva session');
    assert.strictEqual(session.client.ns, 'user');
    assert.strictEqual(await session.eval('(+ 40 2)', 'user').value, '42');
  });

  test('loads a Kvist file with the Calva command', async () => {
    const editor = await testUtil.openFile(testFile);
    assert.strictEqual(editor.document.languageId, 'clojure');
    await editor.edit((edit) => {
      edit.insert(
        editor.document.positionAt(editor.document.getText().length),
        '(def calva-loaded-from-buffer: int 44)\n'
      );
    });
    await vscode.commands.executeCommand('calva.loadFile');
    const replText = (await outputWindow.openReplWindowDoc()).getText();
    try {
      assert.strictEqual(await replSession.getSession().eval('*1', 'user').value, '45');
      assert.strictEqual(
        await replSession.getSession().eval('(+ calva-loaded-from-buffer 1)', 'user').value,
        '45'
      );
      assert.strictEqual(
        await replSession.getSession().eval('(calva-greeting-length "hei")', 'user').value,
        '3'
      );
    } catch (error) {
      assert.fail(
        `Loaded binding unavailable: ${error}\nserver stdout: ${serverOut}\nserver stderr: ${serverErr}\nREPL: ${replText}`
      );
    }
  });

  test('evaluates an ordinary top-level form', async () => {
    const editor = await testUtil.openFile(testFile);
    await outputWindow.clearReplWindowDoc();
    const expression = '(+ calva-loaded 2)';
    const offset = editor.document.getText().indexOf(expression);
    assert.ok(offset >= 0, 'Expected top-level expression in fixture');
    const cursor = editor.document.positionAt(offset + 3);
    editor.selection = new vscode.Selection(cursor, cursor);
    await vscode.commands.executeCommand('calva.evaluateCurrentTopLevelForm');
    await testUtil.waitForCondition(
      async () => (await outputWindow.openReplWindowDoc()).getText().includes('43'),
      10_000,
      50,
      'Calva did not evaluate the top-level Kvist form'
    );
  });

  test('evaluates a top-level selection and exposes the last result', async () => {
    const editor = await testUtil.openFile(testFile);
    await outputWindow.clearReplWindowDoc();
    const expression = '(+ calva-loaded 2)';
    const offset = editor.document.getText().indexOf(expression);
    assert.ok(offset >= 0, 'Expected top-level expression in fixture');
    editor.selection = new vscode.Selection(
      editor.document.positionAt(offset),
      editor.document.positionAt(offset + expression.length)
    );
    await vscode.commands.executeCommand('calva.evaluateSelection');
    await testUtil.waitForCondition(
      async () => (await outputWindow.openReplWindowDoc()).getText().includes('43'),
      10_000,
      50,
      'Calva did not render the Kvist evaluation result'
    );
    await vscode.env.clipboard.writeText('kvist-e2e-sentinel');
    await vscode.commands.executeCommand('calva.copyLastResults');
    await testUtil.waitForCondition(
      async () => (await vscode.env.clipboard.readText()) === '43',
      5_000,
      50,
      'Calva did not copy the last Kvist result'
    );
  });

  test('provides signature help through VS Code', async () => {
    const editor = await testUtil.openFile(testFile);
    const expression = '(println)';
    const offset = editor.document.getText().indexOf(expression);
    assert.ok(offset >= 0, 'Expected println form in fixture');
    const signature = await vscode.commands.executeCommand<vscode.SignatureHelp>(
      'vscode.executeSignatureHelpProvider',
      editor.document.uri,
      editor.document.positionAt(offset + '(println'.length)
    );
    assert.ok(signature?.signatures.length, 'Expected signature help for println');
    assert.ok(
      signature.signatures.some((item) => item.label.includes('println')),
      signature.signatures.map((item) => item.label).join('\n')
    );
  });

  test('provides completion through VS Code', async () => {
    const editor = await testUtil.openFile(testFile);
    const expression = '(pri)';
    const offset = editor.document.getText().indexOf(expression);
    assert.ok(offset >= 0, 'Expected completion form in fixture');
    const completions = await vscode.commands.executeCommand<vscode.CompletionList>(
      'vscode.executeCompletionItemProvider',
      editor.document.uri,
      editor.document.positionAt(offset + '(pri'.length)
    );
    assert.ok(
      completions.items.some((item) =>
        (typeof item.label === 'string' ? item.label : item.label.label).includes('println')
      ),
      'Expected println in Calva completion results'
    );
  });

  test('completes a Kvist definition outside comment forms', async () => {
    const editor = await testUtil.openFile(testFile);
    const insertionOffset = editor.document.getText().length;
    await editor.edit((edit) => {
      edit.insert(editor.document.positionAt(insertionOffset), '\n(calva-g)\n');
    });
    const completions = await vscode.commands.executeCommand<vscode.CompletionList>(
      'vscode.executeCompletionItemProvider',
      editor.document.uri,
      editor.document.positionAt(insertionOffset + '\n(calva-g'.length)
    );
    assert.ok(
      completions.items.some((item) =>
        (typeof item.label === 'string' ? item.label : item.label.label).includes(
          'calva-greeting-length'
        )
      ),
      'Expected the Kvist definition in Calva completion results'
    );
  });

  test('provides hover documentation through VS Code', async () => {
    const editor = await testUtil.openFile(testFile);
    const expression = '(println)';
    const offset = editor.document.getText().indexOf(expression);
    assert.ok(offset >= 0, 'Expected println form in fixture');
    const hovers = await vscode.commands.executeCommand<vscode.Hover[]>(
      'vscode.executeHoverProvider',
      editor.document.uri,
      editor.document.positionAt(offset + 3)
    );
    const hoverText = (hovers ?? [])
      .flatMap((hover) => hover.contents)
      .map((content) => (typeof content === 'string' ? content : content.value))
      .join('\n');
    assert.ok(hoverText.includes('Print values followed by a newline'), hoverText);
  });

  test('provides definition locations through VS Code', async () => {
    const editor = await testUtil.openFile(testFile);
    const expression = '(println)';
    const offset = editor.document.getText().indexOf(expression);
    assert.ok(offset >= 0, 'Expected println form in fixture');
    const definitions = await vscode.commands.executeCommand<
      Array<vscode.Location | vscode.LocationLink>
    >(
      'vscode.executeDefinitionProvider',
      editor.document.uri,
      editor.document.positionAt(offset + 3)
    );
    assert.ok(definitions?.length, 'Expected a definition result');
    const location = definitions[0];
    const uri = location instanceof vscode.Location ? location.uri : location.targetUri;
    assert.ok(uri.fsPath.endsWith(path.join('src', 'kvist', 'core', 'core.kvist')), uri.fsPath);
  });

  test('signals evaluation errors through Calva', async () => {
    await assert.rejects(
      replSession.getSession().eval('(def broken: no-such-type 1)', 'user').value,
      /kvist\.EvaluationError/
    );
  });

  test('interrupts a running Kvist evaluation and recovers', async function () {
    this.timeout(30_000);
    const session = replSession.getSession();
    const evaluation = session.eval('(do (while true (discard 1)) 0)', 'user');
    await new Promise((resolve) => setTimeout(resolve, 250));
    await vscode.commands.executeCommand('calva.interruptAllEvaluations');
    try {
      await evaluation.value;
    } catch (error) {
      assert.fail(
        `Interrupted evaluation failed: ${error}\nmessages: ${JSON.stringify(evaluation.msgs)}\n` +
          `server stdout: ${serverOut}\nserver stderr: ${serverErr}`
      );
    }
    try {
      assert.strictEqual(await session.eval('(+ 1 2)', 'user').value, '3');
    } catch (error) {
      assert.fail(
        `Evaluation after interrupt failed: ${error}\nserver stdout: ${serverOut}\n` +
          `server stderr: ${serverErr}`
      );
    }
  });
});
