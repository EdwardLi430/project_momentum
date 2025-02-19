%% Part A - Data Processing and Preparation

% Clear workspace and close all figures
clear;
close all;

% Read and process 'return_monthly.xlsx'
% This file contains monthly stock returns in percentage terms
return_m_hor = readtable('return_monthly.xlsx', ...
    'ReadVariableNames', true, ...
    'PreserveVariableNames', true, ...
    'Format', 'auto');
num_vars1 = width(return_m_hor);
% Reshape data into long format
return_m_stacked = stack(return_m_hor, 3:num_vars1, ...
    'NewDataVariableName', 'return_m', ...
    'IndexVariableName', 'date');
% Convert and format dates
return_m_stacked.date = char(return_m_stacked.date);
return_m_stacked.datestr = datestr(return_m_stacked.date);
return_m_stacked.date = datetime(return_m_stacked.datestr, ...
    'InputFormat', 'dd-MMM-yyyy', ...
    'Locale', 'en_US');
% Convert returns to decimal format
return_m_stacked.return_m = return_m_stacked.return_m / 100;

% Read and process 'me_lag.xlsx'
% This file includes lagged market capitalization
market_cap_lm_hor = readtable('me_lag.xlsx', ...
    'ReadVariableNames', true, ...
    'PreserveVariableNames', true, ...
    'Format', 'auto');
num_vars2 = width(market_cap_lm_hor);
% Reshape data into long format
market_cap_lm_stacked = stack(market_cap_lm_hor, 3:num_vars2, ...
    'NewDataVariableName', 'lme', ...
    'IndexVariableName', 'date');
% Convert and format dates
market_cap_lm_stacked.date = char(market_cap_lm_stacked.date);
market_cap_lm_stacked.datestr = datestr(market_cap_lm_stacked.date);
market_cap_lm_stacked.date = datetime(market_cap_lm_stacked.datestr, ...
    'InputFormat', 'dd-MMM-yyyy', ...
    'Locale', 'en_US');

% Merge, sort, and clean the data
datatable = outerjoin(return_m_stacked, market_cap_lm_stacked, ...
    'Keys', {'date', 'code'}, ...
    'MergeKeys', true, ...
    'Type', 'left');
datatable = sortrows(datatable, {'code', 'date'}, ...
    {'ascend', 'ascend'});
% Remove rows with missing lagged market capitalization
datatable = datatable(~isnan(datatable.lme), :);
% Save the processed data
save('return_m.mat', 'datatable');

%% Part B - Momentum Analysis

% Load the previously processed dataset
load('return_m.mat');

% User input for frequency of momentum analysis
prompt = 'Enter the number of months for momentum analysis (1, 3, 6, 12, or 24): ';
frequency = input(prompt);

% Validate the user input
valid_frequencies = [1, 3, 6, 12, 24];
if ~ismember(frequency, valid_frequencies)
    error('Invalid input. Please enter 1, 3, 6, 12, or 24.');
end

% Rest of the momentum analysis code
% Group data by date and initialize variables
[G, jdate] = findgroups(datatable.date);
num_obs = length(jdate);
datatable.jdate = G;

% Loop for momentum calculation
oldmomentum = table();
tic % Start timer
for i = frequency
    j = i;
    while j <= num_obs - i
        temp_date = [];
        temp_date_start = floor(j / i) * i - i + 1;
        temp_date_end = floor(j / i) * i - i + i;
        
        % Creating a range of dates for analysis
        while temp_date_start <= temp_date_end
            temp_date = [temp_date, temp_date_start];
            temp_date_start = temp_date_start + 1;
        end

        start_date = j + 1;
        
        % Finding indices of the dates that match with temp_date
        index_i = ismember(datatable.jdate, temp_date);
        index = any(index_i, 2);
        
        % Extracting a subset of data for the current date range
        sample = datatable(index, 1:end);
        
        % Grouping data by 'code' and summing returns for each group
        [G, code] = findgroups(sample.code);
        pr_return = accumarray(G, sample.return_m, [], @sum);
        pr_return_table = table(code, pr_return);

        date_to_match = start_date;
        rindex = datatable.jdate == date_to_match;
        
        % Merging the momentum data with the return data
        rmomentum = datatable(rindex, :);
        momentum_sample1 = outerjoin(rmomentum, pr_return_table, ...
            'Keys', {'code'}, ...
            'MergeKeys', true, ...
            'Type', 'left');
        
        % Concatenating with previous momentum data
        return_full = vertcat(oldmomentum, momentum_sample1);
        oldmomentum = return_full;
        
        j = j + 1;
    end
end

toc % End timer

% Calculate percentiles and create percentile matrix
percentiles = 20:20:80;
percentile_matrix = zeros(size(return_full, 1), length(percentiles));
for i = 1:length(percentiles)
    pct_val = prctile(return_full.pr_return, percentiles(i));
    percentile_matrix(:, i) = pct_val * ones(size(return_full, 1), 1);
end

% Create a table for percentile data
percentile_table = array2table(percentile_matrix, ...
    'VariableNames', arrayfun(@(x) ['m' num2str(x)], percentiles, ...
    'UniformOutput', false));
return_full = [return_full, percentile_table];

% Assign momentum labels
return_full.mlabel = rowfun(@m_bucket, return_full(:, {'pr_return', 'm20', 'm40', 'm60', 'm80'}), ...
    'OutputFormat', 'cell');
return_full.ew = ones(height(return_full), 1);

% Group and calculate equal-weighted return
[G, jdate, mlabel] = findgroups(return_full.date, return_full.mlabel);
wret = splitapply(@wavg, return_full(:, {'return_m', 'ew'}), G);
wret_table = table(jdate, mlabel, wret);
% Unstack the data for momentum factors
mfactors = unstack(wret_table(:, {'wret', 'jdate', 'mlabel'}), 'wret', 'mlabel');
% Calculate average returns
Low = mean(table2array(mfactors(:, 2)), 'omitnan') * 100;
High = mean(table2array(mfactors(:, 6)), 'omitnan') * 100;

% Display results
fprintf('Momentum Analysis for a %d-month Period:\n', frequency);
fprintf('  - Portfolio with historically lower returns: Average monthly return = %.3f%%\n', Low);
fprintf('  - Portfolio with historically higher returns: Average monthly return = %.3f%%\n', High);

%% Part C - Principal Component Analysis (PCA)

% Prepare data for PCA
momentum = table2array(mfactors(:, 2:6));
% Perform PCA
[coefMatrix, ~, ~, ~, explainedVar] = pca(momentum);
% Project data onto PCA factors
PCAfactors = momentum * coefMatrix(:, 1:5);

% Plot PCA factor loadings
figure;
plot(coefMatrix(:, 1:3), '-x');
legend('First Factor', 'Second Factor', 'Third Factor');
xlabel('Principal Components');
ylabel('Coefficient Values');
title('PCA Factor Loadings');

% Compute correlations with MOMENTUM factor
m = momentum(:, 5) - momentum(:, 1);
% Store correlation values
corr_values = zeros(5, 1);
for i = 1:5
    corr_values(i) = corr(PCAfactors(:, i), m);
end
% Create and display correlation table
corr_table = array2table(corr_values, 'VariableNames', {'Correlation_with_MOM'});
corr_table.PrincipalComponent = {'First Factor'; 'Second Factor'; 'Third Factor'; 'Fourth Factor'; 'Fifth Factor'};
corr_table = corr_table(:, {'PrincipalComponent', 'Correlation_with_MOM'});
disp(corr_table);