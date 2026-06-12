/**
 * This is the entry point for the extension.
 */

import { setupCa } from "core/util/ca";
import * as vscode from "vscode";

export { default as buildTimestamp } from "./.buildTimestamp";

let activation: Promise<unknown> | undefined;

async function dynamicImportAndActivate(context: vscode.ExtensionContext) {
  await setupCa();
  const { activateExtension } = await import("./activation/activate");
  return await activateExtension(context);
}

function handleActivationError(error: unknown) {
  activation = undefined;
  void import("./activation/activate").then(({ resetActivationState }) => {
    resetActivationState();
  });

  console.log("Error activating extension: ", error);
  void vscode.window
    .showWarningMessage(
      "Error activating the Continue extension.",
      "View Logs",
      "Retry",
    )
    .then((selection) => {
      if (selection === "View Logs") {
        void vscode.commands.executeCommand("continue.viewLogs");
      } else if (selection === "Retry") {
        void vscode.commands.executeCommand("workbench.action.reloadWindow");
      }
    });
}

export function activate(context: vscode.ExtensionContext) {
  if (!activation) {
    activation = dynamicImportAndActivate(context);
  }
  return activation.catch(handleActivationError);
}

export function deactivate() {
  activation = undefined;
  void import("./activation/activate").then(({ resetActivationState }) => {
    resetActivationState();
  });
}
