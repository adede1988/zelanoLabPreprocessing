function inh = countInhales_detectNoOdor(R, TTL, fs, opts)
%COUNTINHALES_DETECTNOODOR  Number of inhales between the SNIFF cue and the answer, per trial.
%
%   inh = countInhales_detectNoOdor(R, TTL, fs, opts)
%
%   R    : preprocess_respiration_wholetrace output (R.rspDat = the session's
%          respiration channel at fs, already flipped inhale-up)
%   TTL  : the detectNoOdor TTL table (sniff, response; final samples)
%   opts : optional struct (P.inhaleOpts), fields (defaults):
%     smoothSec  0.1   Gaussian smoothing of R.rspDat before peak picking
%     baseSec    1     baseline = median of the smoothed trace over [cue - baseSec, cue]
%     promFrac   0.25  an inhale = a peak inside the window whose prominence AND
%                      height above the baseline are both >= promFrac x the
%                      trial's largest height above the baseline in the window
%     keepFrac   0.05  peaks stored for re-thresholding: prominence >= keepFrac x that
%
%   Window: [SNIFF cue, button-response pulse] (the attempt-to-detect period); NaN
%   for a trial without a response pulse. The count is DATA, not a reading of the
%   answer: a "double sniff" is two inhale peaks separated by a dip of at least
%   promFrac of the sniff's height. The count depends on promFrac for trials with
%   a shoulder or a shallow notch; inh.peaks keeps every candidate peak (time
%   from the cue, height above baseline, prominence, both as a fraction of the
%   trial's maximum) so the count can be redone at another threshold.
%
%   inh: struct with opts, method, window (trial, startSample, endSample),
%        nInhales [nTrial x 1], peaks (table: trial, tSec, height, prominence,
%        heightFrac, promFrac, counted), amp [nTrial x 1] (max height above
%        baseline in the window).

    if nargin < 4 || isempty(opts), opts = struct; end
    d = struct('smoothSec', 0.1, 'baseSec', 1, 'promFrac', 0.25, 'keepFrac', 0.05);
    fn = fieldnames(d);
    for i = 1:numel(fn)
        if ~isfield(opts, fn{i}), opts.(fn{i}) = d.(fn{i}); end
    end

    x = smoothdata(R.rspDat, 'gaussian', max(1, round(opts.smoothSec * fs)));
    T = numel(x);
    nT = height(TTL);
    nInh = nan(nT, 1); amp = nan(nT, 1);
    w0 = TTL.sniff(:); w1 = TTL.response(:);
    pk = {};
    for t = 1:nT
        if isnan(w0(t)) || isnan(w1(t)), continue; end
        b0 = max(1, w0(t) - round(opts.baseSec * fs));
        if w1(t) > T, error('countInhales_detectNoOdor:range', 'trial %d window past the data', t); end
        b = median(x(b0:w0(t)));
        seg = x(w0(t):w1(t));
        A = max(seg) - b;
        amp(t) = A;
        [p, l, ~, pr] = findpeaks(seg);
        h = p(:) - b; pr = pr(:); l = l(:);
        if A <= 0 || isempty(p)
            nInh(t) = 0; continue
        end
        counted = pr >= opts.promFrac * A & h >= opts.promFrac * A;
        nInh(t) = sum(counted);
        kp = pr >= opts.keepFrac * A;
        pk{end+1, 1} = table(repmat(t, sum(kp), 1), (l(kp) - 1) / fs, h(kp), pr(kp), ...
            h(kp) / A, pr(kp) / A, counted(kp), 'VariableNames', ...
            {'trial', 'tSec', 'height', 'prominence', 'heightFrac', 'promFrac', 'counted'}); %#ok<AGROW>
    end
    inh = struct;
    inh.opts = opts;
    inh.method = sprintf(['peaks of the respiration (R.rspDat, inhale up, %g-s Gaussian) between the SNIFF cue ' ...
        'and the response pulse with prominence and height above the pre-cue baseline (median of %g s) ' ...
        '>= %g x the trial''s maximum height; NaN = no response'], opts.smoothSec, opts.baseSec, opts.promFrac);
    inh.window = table((1:nT)', w0, w1, 'VariableNames', {'trial', 'startSample', 'endSample'});
    inh.nInhales = nInh;
    inh.amp = amp;
    if isempty(pk)
        inh.peaks = table('Size', [0 7], 'VariableTypes', {'double', 'double', 'double', 'double', 'double', 'double', 'logical'}, ...
            'VariableNames', {'trial', 'tSec', 'height', 'prominence', 'heightFrac', 'promFrac', 'counted'});
    else
        inh.peaks = vertcat(pk{:});
    end
end
