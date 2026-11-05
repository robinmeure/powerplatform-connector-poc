function Assert-ConnectorSecurityUnchanged {
    param([Parameter(Mandatory)]$Before, [Parameter(Mandatory)]$After)
    foreach ($field in @('connectionparameters', 'connectionparametersets', 'policytemplateinstances')) {
        if ($Before.$field -ne $After.$field) {
            throw "Connector security metadata changed unexpectedly: $field."
        }
    }
}
