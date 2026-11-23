%% run_AP4_model_03.m - AP4 2017 baseline + 11 proposed NC units
%
% Run from the nc-duke-power-plants-ap4 project ROOT:
%   run('R/run_AP4_model_03.m')
%
% No changes to the original AP4 scripts or 2017 emissions inventory.
% Adds only the 11 proposed units' 2024-benchmark emissions. AP4 baseline
% population, mortality rates, chemistry and willingness-to-pay remain 2017.
%
% Source assumptions (explicitly accepted for this study):
%  Person -> existing EGU row 1174; Marshall -> 1366; Buck -> 1416;
%  Smith -> 1405; Belews Creek -> 1418.
%  Davie -> county FIPS 37059 non-EGU POINT-SOURCE row (not ground-level).
%  Davie modeling coordinate: 35.84273333 N, -80.41536111 W; the generic
%  county-source coefficients do NOT use these coordinates.
%
% Outputs are mortality and dollar damages at 2020 AP4 USD valuation (NOT
%  yet 2026 USD); convert consistently in the next R script. Combined
%  scenario results are the primary output. Standalone site and pollutant
%  counterfactuals need NOT sum to the combined scenario due to chemistry.
%
% REQUIRED files:
%   data/raw/AP4/AP4 Model/AP4_Control_Workspace.mat
%   data/raw/AP4/AP4 Model/*.m (original AP4 scripts)
%   data/raw/AP4/AP4 Model/AP4_inputs/AP4_County_List.xlsx
%   data/intermediate/unit_emissions.csv (from R/02_plant_emissions.R)
%
% AP4's Load_Workspace.m executes CLEAR. Therefore do not configure any
% scenario variables until AFTER the original baseline is calculated.

%% 1. Original baseline and health specification
%% Set the correct project directory

projectRoot = '/Users/marcozamudio/Desktop/AP4 Research/nc-duke-power-plants-ap4';

cd(projectRoot);

fprintf('Current project directory: %s\n', pwd);

%% 1. Original baseline and health specification

assert(isfile(fullfile('data','raw','AP4','AP4 Model', ...
    'PM_25_Base_Concentration.m')), ...
    'Run this script from the repository root. Original AP4 files not found.');
fprintf('Step 1/5: Running unmodified AP4 baseline...\n');
run(fullfile('data','raw','AP4','AP4 Model','PM_25_Base_Concentration.m'));
run(fullfile('data','raw','AP4','AP4 Model','AP4_Setup.m'));

assert(exist('PM_25_Base','var') == 1 && numel(PM_25_Base) == 3108, ...
    'AP4 baseline was not computed correctly.');
assert(all(isfinite(PM_25_Base(:))) && all(PM_25_Base(:) >= 0), ...
    'Invalid AP4 baseline concentrations.');
fprintf('MATLAB AP4 baseline min/median/max: %.6f / %.6f / %.6f\n', ...
    min(PM_25_Base), median(PM_25_Base), max(PM_25_Base));

% Check native model baseline against user's previously observed values.
assert(abs(median(PM_25_Base) - 6.646387) < 0.01, ...
    'AP4 baseline differs from previously verified reference. Stop and investigate.');
assert(exist('wtp','var') == 1 && isscalar(wtp) && wtp > 0, ...
    'AP4_Setup.m did not calculate a valid WTP.');
assert(exist('usd_year','var') == 1 && usd_year == 2020, ...
    'Expected AP4 valuation in 2020 USD; verify AP4_Setup.m.');

%% 2. Read inputs and assert exact mapping
fprintf('Step 2/5: Validating 11 proposed units and AP4 source rows...\n');
unitsFile = fullfile('data','intermediate','unit_emissions.csv');
assert(isfile(unitsFile), 'Missing unit_emissions.csv - run R/02_plant_emissions.R first.');
T = readtable(unitsFile);
requiredCols = {'site_name','county_fips','nox_tons','so2_tons'};
assert(all(ismember(requiredCols, T.Properties.VariableNames)), ...
    'unit_emissions.csv missing required columns.');
assert(height(T) == 11, 'Expected emissions for exactly 11 proposed units.');
site = string(T.site_name);
siteNames = ["Person"; "Davie"; "Marshall"; "Buck"; "Smith"; "Belews Creek"];
assert(numel(unique(site)) == 6 && isequal(sort(unique(site)), sort(siteNames)), ...
    'Site names do not match the six proposed locations.');
assert(all(isfinite(T.nox_tons)) && all(isfinite(T.so2_tons)) && ...
       all(T.nox_tons >= 0) && all(T.so2_tons >= 0), ...
    'Annual proposed-unit emissions must be finite and nonnegative.');

% AP4 uses METRIC tonnes; R/02_plant_emissions.R reports US short tons.
shortTonToMetric = 2000 / 2204.62262185;
emNOx = zeros(6,1);
emSO2 = zeros(6,1);
unitCount = zeros(6,1);
for j = 1:6
    matching = site == siteNames(j);
    unitCount(j) = sum(matching);
    emNOx(j) = sum(T.nox_tons(matching)) * shortTonToMetric;
    emSO2(j) = sum(T.so2_tons(matching)) * shortTonToMetric;
end
assert(isequal(unitCount, [2;2;2;2;1;2]), 'Unexpected proposed unit counts.');

% Verify AP4 county matrix row for Davie; NEVER infer it from county FIPS.
countyFile = fullfile('data','raw','AP4','AP4 Model','AP4_inputs','AP4_County_List.xlsx');
assert(isfile(countyFile), 'Missing AP4_County_List.xlsx in AP4_inputs.');
countyTable = readtable(countyFile);
assert(all(ismember({'row','fips'}, countyTable.Properties.VariableNames)), ...
    'County crosswalk must have row and fips columns.');
assert(height(countyTable) == 3108 && ...
    isequal(double(countyTable.row(:)), (1:3108)'), 'County rows do not match AP4 indexing.');
fips = double(countyTable.fips);
ncMask = floor(fips / 1000) == 37;
ncRows = find(ncMask);
assert(numel(ncRows) == 100, 'Expected exactly 100 NC receptor counties.');
davieRow = find(fips == 37059);
assert(isscalar(davieRow), 'Davie County must map to exactly one AP4 county row.');

% Each row applies to one proposed site, not an existing unit's emissions.
sourceType = ["EGU";"NON_EGU_POINT_COUNTY_PROXY";"EGU";"EGU";"EGU";"EGU"];
sourceRow = [1174; davieRow; 1366; 1416; 1405; 1418];
assert(size(SR_Matrices_Point_EGU{2,1},1) == 1814 && ...
       size(SR_Matrices_Point_Non_EGU{2,1},1) == 3108, ...
       'Unexpected AP4 source matrix dimensions.');

% Save unperturbed EGU and non-EGU precursor concentrations for repeated
% counterfactuals; NEVER overwrite the original 2017 emissions inventory.
HNO3_reference = HNO3;
SO4_reference = SO4;

%% 3. Combined 11-unit scenario, followed by individual counterfactuals
fprintf('Step 3/5: Calculating combined and standalone AP4 scenarios...\n');
% Scenarios: 1 = all 11 units; 2..7 = each site separately;
% 8 = all NOx only; 9 = all SO2 only.
scenarioNames = ["All_11_Units"; siteNames; "All_NOx_Only"; "All_SO2_Only"];
nScenario = numel(scenarioNames);
scenarioAdult = zeros(3108, nScenario);
scenarioInfant = zeros(3108, nScenario);
scenarioPM25 = zeros(3108, nScenario);

for k = 1:nScenario
    % Start each scenario from exactly the same ambient 2017 baseline.
    HNO3 = HNO3_reference;
    SO4 = SO4_reference;
    for j = 1:6
        includeSite = k == 1 || k == j+1 || k == 8 || k == 9;
        if ~includeSite
            continue
        end
        includeNOx = k ~= 9;
        includeSO2 = k ~= 8;
        if sourceType(j) == "EGU"
            pcol = 3; % Third column = EGU point source
            noxVector = SR_Matrices_Point_EGU{2,1}(sourceRow(j), :)';
            so2Vector = SR_Matrices_Point_EGU{4,1}(sourceRow(j), :)';
        else
            pcol = 2; % Second column = non-EGU county point source
            noxVector = SR_Matrices_Point_Non_EGU{2,1}(sourceRow(j), :)';
            so2Vector = SR_Matrices_Point_Non_EGU{4,1}(sourceRow(j), :)';
        end
        if includeNOx
            HNO3(:, pcol) = HNO3(:, pcol) + ...
                NOx_Cal_base .* emNOx(j) .* noxVector;
        end
        if includeSO2
            SO4(:, pcol) = SO4(:, pcol) + ...
                SO2_Cal_base .* emSO2(j) .* so2Vector;
        end
    end

    % Original AP4 secondary PM chemistry and spatial mortality routines.
    run(fullfile('data','raw','AP4','AP4 Model','Nitrate_Sulfate_Ammonium_Update.m'));
    Delta_PM_25 = PM_25 - PM_25_Base;
    if any(~isfinite(Delta_PM_25(:)))
        error('Nonfinite incremental PM2.5 in scenario %s', scenarioNames(k));
    end
    run(fullfile('data','raw','AP4','AP4 Model','PM_25_Health.m'));
    scenarioPM25(:, k) = Delta_PM_25;
    scenarioAdult(:, k) = Adult_Deaths;
    scenarioInfant(:, k) = Infant_Deaths;
    fprintf('  %s: NC incremental PM2.5 median %.9f ug/m3\n', ...
        scenarioNames(k), median(Delta_PM_25(ncRows)));
end

%% 4. Export 100-county health impact results, preserving scenario identity
fprintf('Step 4/5: Exporting county-level mortality and damages...\n');
outDir = fullfile('data','intermediate','ap4_nc');
if ~isfolder(outDir)
    mkdir(outDir);
end
nfips = compose('%05d', fips(ncRows));
allOutputs = table();
for k = 1:nScenario
    n = numel(ncRows);
    davieIncluded = k == 1 || k == 3 || k == 8 || k == 9;
    if davieIncluded
        davieStatus = "NON_EGU_POINT_COUNTY_PROXY_INCLUDED";
    else
        davieStatus = "DAVIE_NOT_INCLUDED_IN_THIS_SCENARIO";
    end
    result = table(repmat(scenarioNames(k),n,1), nfips, ...
        repmat(davieStatus,n,1), ...
        PM_25_Base(ncRows), scenarioPM25(ncRows,k), ...
        scenarioAdult(ncRows,k), scenarioInfant(ncRows,k), ...
        scenarioAdult(ncRows,k) + scenarioInfant(ncRows,k), ...
        wtp .* (scenarioAdult(ncRows,k) + scenarioInfant(ncRows,k)), ...
        'VariableNames', {'scenario','receptor_fips','davie_source_approximation', ...
        'baseline_pm25_ug_m3','delta_pm25_ug_m3', ...
        'adult_expected_deaths','infant_expected_deaths', ...
        'total_expected_deaths','mortality_damage_2020_usd'});
    allOutputs = [allOutputs; result]; %#ok<AGROW>
end
writetable(allOutputs, fullfile(outDir,'ap4_nc_scenario_results_2020usd.csv'));

% Explicit source/assumption manifest for reproducibility.
sourceManifest = table(siteNames, unitCount, sourceType, sourceRow, ...
    emNOx, emSO2, 'VariableNames', ...
    {'site_name','proposed_units','ap4_source_type','ap4_source_row_1based', ...
     'nox_metric_tonnes','so2_metric_tonnes'});
writetable(sourceManifest, fullfile(outDir,'ap4_proposed_sources_manifest.csv'));

%% 5. Report scenario totals (NC receptors only) and limitations
fprintf('Step 5/5: Results and validation summary.\n');
for k = 1:nScenario
    d = sum(scenarioAdult(ncRows,k) + scenarioInfant(ncRows,k));
    fprintf('%-20s | NC expected deaths: %.8f | AP4 2020 USD: $%.2f\n', ...
        scenarioNames(k), d, wtp*d);
end
fprintf('\nIMPORTANT: source dispersion uses accepted proxies, including Davie county-level non-EGU point source.\n');
fprintf('Standalone site and pollutant scenarios are NONADDITIVE due to AP4 chemistry.\n');
fprintf('AP4 2017 baseline with 2024 CEMS operating benchmarks; valuations are 2020 USD.\n');
fprintf('Export: %s\n', fullfile(outDir,'ap4_nc_scenario_results_2020usd.csv'));
