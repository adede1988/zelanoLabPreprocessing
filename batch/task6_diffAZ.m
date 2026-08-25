% task6_diffAZ — Task 6 Part A step 3 backward-compatibility check.
% Compares the freshly rerun 230611_OBE_NMH_AZ cue final against the July
% backup: every shared behDat column must be identical (the noCue change must
% not perturb sessions without cue==0 trials).

ID = '230611_OBE_NMH_AZ';
NEW = fullfile(labPaths().rootOBE, ID, 'preProc', [ID '_cueTaskPreproc.mat']);
OLD = fullfile('E:\reprocBackup_260824\cue', [ID '_cueTaskPreproc.mat']);

Sn = load(NEW); fn = fieldnames(Sn); newDat = Sn.(fn{1}); clear Sn
So = load(OLD); fn = fieldnames(So); oldDat = So.(fn{1}); clear So

nb = newDat.behDat; ob = oldDat.behDat;
fprintf('new behDat: %d x %d | old behDat: %d x %d\n', height(nb), width(nb), height(ob), width(ob));
assert(height(nb) == height(ob), 'row count differs');

shared = intersect(nb.Properties.VariableNames, ob.Properties.VariableNames);
onlyNew = setdiff(nb.Properties.VariableNames, ob.Properties.VariableNames);
onlyOld = setdiff(ob.Properties.VariableNames, nb.Properties.VariableNames);
fprintf('columns only in new: {%s}\ncolumns only in old: {%s}\n', ...
    strjoin(onlyNew, ','), strjoin(onlyOld, ','));

nDiff = 0;
for c = 1:numel(shared)
    a = nb.(shared{c}); b = ob.(shared{c});
    if isequaln(a, b)
        continue;
    end
    % numeric columns: tolerate tiny float noise
    if isnumeric(a) && isnumeric(b) && isequal(size(a), size(b)) ...
            && max(abs(double(a(:)) - double(b(:))), [], 'omitnan') < 1e-9 ...
            && isequaln(isnan(double(a(:))), isnan(double(b(:))))
        continue;
    end
    nDiff = nDiff + 1;
    fprintf('DIFFERS: %s\n', shared{c});
end
fprintf('type counts new: '); disp(groupcounts(nb, 'type'));
if nDiff == 0
    fprintf('task6_diffAZ: PASS - all %d shared behDat columns identical\n', numel(shared));
else
    fprintf('task6_diffAZ: FAIL - %d columns differ\n', nDiff);
end

% quick structural checks of the new final
assert(isfield(newDat, 'moreThan1') && ismember('manOnset', nb.Properties.VariableNames), ...
    'new final missing moreThan1/manOnset');
fprintf('new final fs=%d moreThan1=%d\n', newDat.fs, newDat.moreThan1);
