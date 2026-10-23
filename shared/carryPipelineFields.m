function f = carryPipelineFields()
%CARRYPIPELINEFIELDS  Every top-level outDat field the pipeline itself can produce (any task, any configuration).
%
%   f = carryPipelineFields()      % column cellstr, sorted
%
%   The exclusion set of the respiration carry (carryFinishFromFinal). A field of
%   the previous final that the new run did not produce is a "post-hoc" field
%   (an analysis or edit made on that final afterwards: bestMac, ridgeInfo,
%   powerPhaseContinuity, ...) and goes to outDat.carriedFromPrevFinal -
%   UNLESS the pipeline can produce it in some configuration, in which case its
%   absence from the new run is a decision of this run's configuration, not a
%   gap: e.g. blinkICA / EEGCleaningInfo when blink removal or the EEG stage is
%   off (251027_Dupi_NMH_DL_1 breathingTask since G2f), heartBeats when the ECG
%   stage was skipped, the vipassana / ADmeditation / airPuff extras on a final
%   of another task. Such a field is NOT carried (carrying it would present the
%   previous run's EEG / ECG / segmentation results as if this run had made
%   them); its name is listed in outDat.carry.stageFieldsNotCarried.
%
%   The set is the union of every `outDat.<field> = ...` the code under
%   pipelines/, shared/, tasks/ and config/ writes, grouped by who writes it.
%   batch/testCarryRespFromFinal rescans the repo and fails when a field is
%   written that is not listed here: add a new outDat field to this list in the
%   same commit that introduces it.
%
%   Deliberately NOT in the set:
%     reconstructedBlocks  written by the post-hoc tool batch/reconstructPacedBlocks;
%                          the carry copies it for a single recording
%                          (carryRespFromFinal), and a sep final that has it is
%                          kept in carriedFromPrevFinal.
%     carry, carriedFromPrevFinal   the carry's own records (handled explicitly).
%   Never produced by the current pipeline and so carried when a final has them:
%   bestMac, bestMacMethod, powerPhaseContinuity, ridgeInfo (O15 finals GH_2 / PD_1)
%   and any other field of an analysis run on a final afterwards.

    f = {
        % --- assembleOutDat / makeOutDat / the mains: identity, provenance, task records ---
        'sessID'; 'task'; 'type'; 'figs'; 'fs'; 'origFS'; 'downsampled'; 'data'; 'labels'; 'rspIDX'; 'rspFlip'
        'TTL'; 'behDat'; 'moreThan1'; 'surrogateTTL'
        'tim'                                    % legacy time vector: downsample_data keeps it when a final has one
        'CSClist'; 'OGdataDir'; 'loadFile'; 'preProcScript'; 'atlasSegments'; 'atlasFolder'; 'acqSegments'
        'behFiles'; 'behSource'; 'psychopyFiles'; 'segments'; 'segmentsRaw'
        'threshDesign'; 'droppedTrials'; 'noOdorTrials'; 'sniffTrain'; 'ttlInfo'; 'buttonDown'; 'inhaleCount'
        'clipCheck'; 'logAlign'; 'blocks'; 'blockInference'; 'blockMergeInfo'
        'holds'; 'holdInfo'; 'pulses'; 'puffInfo'; 'puffOpts'; 'breaths'
        'baseEmotion'; 'ratings'; 'postSweepEmotion'; 'TTLinfo'
        % --- shared EEG stage (preprocess_eeg: detector, blink ICA, Laplacian) ---
        'EEGCleaning'; 'EEGCleaningInfo'; 'EEGInterpolation'; 'badChans'; 'eegLocs'
        'blinkICA'; 'blinkRemoval'; 'blinkRemovalNote'
        'dataLap'; 'dataLapFromInterp'; 'dataLapGeometry'
        % --- shared macro stage (preprocess_macros) ---
        'spikeRemoval'; 'spikeCleanInfo'
        % --- ECG stage (processECG / runECGStage / flagBadBreaths) ---
        'heartBeats'; 'beatSpec'; 'ecgExclude'; 'ecgEctopic'; 'ecgSkipped'
        % --- breath segmentation, merge and respiration records ---
        'bmObj'; 'bmFeatures'; 'breathMerge'; 'cyclicSighRefractory'; 'rspPolarityRSA'
        'respSkipped'; 'respNote'; 'respProbe'; 'rspFilterHz'; 'rspFilterNote'
        % --- breathingTasks_separate (concatSections / main) ---
        'sections'; 'eegQCPerSection'; 'rspSelectedNote'; 'trimNote'; 'blinkNote'; 'echemNote'; 'sepEchem'
        % --- vipassana ---
        'artifactIndex'; 'avgRef'; 'czRezeroed'; 'dataRef'; 'ecgNotchHz'; 'ecgNotchNote'; 'notchHz'; 'notchNote'
        'header'; 'markers'; 'photodiode'; 'protocol'; 'refChan'; 'sniffLogic'
        % --- ADmeditation ---
        'trim'; 'buttonPresses'; 'pressInfo'
        };
    f = sort(f(:));
end
