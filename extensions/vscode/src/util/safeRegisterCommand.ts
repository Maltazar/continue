import * as vscode from "vscode";

export async function safeRegisterCommand(
  context: vscode.ExtensionContext,
  command: string,
  callback: (...args: unknown[]) => unknown,
  existingCommands: Set<string>,
): Promise<void> {
  if (existingCommands.has(command)) {
    return;
  }

  try {
    context.subscriptions.push(
      vscode.commands.registerCommand(command, callback),
    );
    existingCommands.add(command);
  } catch (error) {
    console.warn(`[Continue] Skipping command ${command}:`, error);
  }
}
