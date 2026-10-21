// Reviewed, offline check plans. None of these classes receives an executor,
// filesystem, model, permission store, memory owner, or application-state port.
export class BaseHarness {
  checks() { return ['verify-current-context']; }
}

export class ArtifactHarness extends BaseHarness {
  checks() { return [...super.checks(), 'check-artifact-exists', 'check-artifact-format']; }
}

export class SpreadsheetHarness extends ArtifactHarness {
  checks() { return [...super.checks(), 'check-saved-cell-values', 'check-percentage-units']; }
}

export class ApiSchemaHarness extends BaseHarness {
  checks() { return [...super.checks(), 'check-tool-schema', 'check-tool-result']; }
}

export const BUILTINS = Object.freeze({
  base: Object.freeze({ parentId: null, type: BaseHarness }),
  artifact: Object.freeze({ parentId: 'base', type: ArtifactHarness }),
  spreadsheet: Object.freeze({ parentId: 'artifact', type: SpreadsheetHarness }),
  'api-schema': Object.freeze({ parentId: 'base', type: ApiSchemaHarness }),
});
