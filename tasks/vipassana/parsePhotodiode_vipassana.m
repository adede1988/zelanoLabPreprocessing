function PD = parsePhotodiode_vipassana(pd, fs, opts)
%PARSEPHOTODIODE_VIPASSANA  Block periods from the vipassana v2 photodiode.
%
%   PD = parsePhotodiode_vipassana(pd, fs)
%   PD = parsePhotodiode_vipassana(pd, fs, opts)
%
%   pd : the BrainVision 'photoDiode' channel (1 x N at fs, as recorded - the
%        raw 'event' row of raw_vipassana.mat). Must be the UNFILTERED trace:
%        the shared core's 0.03-Hz high-pass (time constant ~5 s) would decay
%        the 5-15-min plateaus, so assembleRaw_vipassana calls this before
%        runSharedCore.
%
%   The v2 PsychoPy script (mindfulBreathing) draws a white square under the
%   sensor for the whole of every block (audiobook / paced breathing /
%   meditation) and a black one during the instructions, breaks and
%   questionnaires, so the channel sits on a HIGH plateau during each block
%   and on a LOW one between blocks (all seven sessions of 2026-09-27 ..
%   2026-10-18; the high level wanders a little with room light in some).
%
%   Method
%     1. 50-ms running median (screen-refresh ripple, spikes);
%     2. two levels: Otsu split of the 0.5-99.5 % range, then lo / hi = the
%        medians of the samples below / above the split; threshold = their
%        midpoint (half height); requires hi - lo >= opts.minStep x the
%        noise (robust SD of the first difference) - else no usable marks;
%     3. high runs, bridging dips shorter than opts.bridgeSec (0.5 s);
%        runs >= opts.minRunSec (60 s) are block periods, shorter ones are
%        listed as flickers;
%     4. edges timed on the 5-ms-median trace: the first sample at / above
%        (onset) or the last sample at / above (offset) the threshold within
%        +-opts.edgeSearchSec of the 50-ms edge.
%
%   Returns PD with
%     .runs      table: on, off (samples at fs, 1-based; off = last high
%                sample), onSec, offSec (s, 0 = first sample), durSec, atStart /
%                atEnd (the run is cut off by the recording's first / last
%                sample: high there, so its true onset / offset is unknown)
%     .flickers  table of the shorter high runs (same columns)
%     .lo, .hi, .thr, .noise, .usable, .opts
%     .trace, .traceFs   the 50-ms-median trace decimated to 10 Hz (QC)

    if nargin < 3 || isempty(opts), opts = struct(); end
    opts = fillDefaults(opts, struct('medSec', 0.05, 'fineMedSec', 0.005, 'bridgeSec', 0.5, ...
        'minRunSec', 60, 'edgeSearchSec', 0.2, 'minStep', 20));

    pd = double(pd(:))';
    N = numel(pd);
    s = movmedian(pd, max(1, round(opts.medSec * fs)));

    q = prctile(s, [0.5 99.5]);
    edges = linspace(q(1), q(2), 257);
    cnt = histcounts(min(max(s, q(1)), q(2)), edges);
    ctr = (edges(1:end - 1) + edges(2:end)) / 2;
    best = -inf; split = mean(q);
    for k = 1:numel(ctr) - 1
        w0 = sum(cnt(1:k)); w1 = sum(cnt(k + 1:end));
        if w0 == 0 || w1 == 0, continue; end
        m0 = sum(cnt(1:k) .* ctr(1:k)) / w0; m1 = sum(cnt(k + 1:end) .* ctr(k + 1:end)) / w1;
        v = w0 * w1 * (m0 - m1) ^ 2;
        if v > best, best = v; split = (edges(k + 1)); end
    end
    PD = struct();
    PD.lo = median(s(s < split));
    PD.hi = median(s(s >= split));
    PD.thr = (PD.lo + PD.hi) / 2;
    PD.noise = 1.4826 * mad(diff(pd), 1) / sqrt(2);
    PD.usable = (PD.hi - PD.lo) >= opts.minStep * max(PD.noise, eps);
    PD.opts = opts;
    % a 10-Hz copy of the 50-ms-median trace for QC figures (the stored
    % 'event' row is high-passed by the shared core)
    PD.traceFs = 10;
    PD.trace = s(1:round(fs / PD.traceFs):end);
    empty = table(zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), false(0, 1), false(0, 1), ...
        'VariableNames', {'on', 'off', 'onSec', 'offSec', 'durSec', 'atStart', 'atEnd'});
    PD.runs = empty; PD.flickers = empty;
    if ~PD.usable
        fprintf('parsePhotodiode_vipassana: no usable step (lo %.0f, hi %.0f, noise %.1f)\n', PD.lo, PD.hi, PD.noise);
        return
    end

    hiM = s >= PD.thr;
    d = diff([false, hiM, false]);
    on = find(d == 1); off = find(d == -1) - 1;
    % bridge short dips
    k = 1;
    while k < numel(on)
        if (on(k + 1) - off(k) - 1) / fs < opts.bridgeSec
            off(k) = off(k + 1); on(k + 1) = []; off(k + 1) = [];
        else
            k = k + 1;
        end
    end
    % refine the edges on a lightly smoothed trace
    f = movmedian(pd, max(1, round(opts.fineMedSec * fs)));
    w = round(opts.edgeSearchSec * fs);
    for k = 1:numel(on)
        a = max(1, on(k) - w); b = min(N, on(k) + w);
        i = find(f(a:b) >= PD.thr, 1, 'first');
        if ~isempty(i), on(k) = a + i - 1; end
        a = max(1, off(k) - w); b = min(N, off(k) + w);
        i = find(f(a:b) >= PD.thr, 1, 'last');
        if ~isempty(i), off(k) = a + i - 1; end
    end
    dur = (off - on + 1) / fs;
    % a run already high at the first sample / still high at the last one is
    % cut off by the recording edge (its true onset / offset is unknown)
    atStart = false(size(on)); atEnd = false(size(on));
    if ~isempty(on)
        atStart(1) = s(1) >= PD.thr;
        atEnd(end) = s(end) >= PD.thr;
    end
    T = table(on(:), off(:), (on(:) - 1) / fs, (off(:) - 1) / fs, dur(:), atStart(:), atEnd(:), ...
        'VariableNames', {'on', 'off', 'onSec', 'offSec', 'durSec', 'atStart', 'atEnd'});
    long = T.durSec >= opts.minRunSec;
    PD.runs = T(long, :);
    PD.flickers = T(~long, :);
    fprintf('parsePhotodiode_vipassana: lo %.0f / hi %.0f uV (thr %.0f, noise %.1f): %d block runs (%s min), %d flickers\n', ...
        PD.lo, PD.hi, PD.thr, PD.noise, height(PD.runs), mat2str(round(PD.runs.durSec' / 60, 2)), height(PD.flickers));
end

function s = fillDefaults(s, d)
    f = fieldnames(d);
    for k = 1:numel(f)
        if ~isfield(s, f{k}) || isempty(s.(f{k})), s.(f{k}) = d.(f{k}); end
    end
end
