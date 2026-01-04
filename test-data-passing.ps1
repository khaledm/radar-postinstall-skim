BeforeAll {
    param($Manifest)
    $script:TestManifest = $Manifest
}
Describe 'Test Data' {
    It 'Should receive manifest data' {
        $script:TestManifest | Should -Not -BeNullOrEmpty
        $script:TestManifest.EnvironmentName | Should -Be 'DEV'
    }
}