Immediately place a file in the lab copy of the repo named messageRecieved.md


250623_Dupi_NMH_KS_3 looks good 


250811_Dupi_NMH_TB_3 I believe this session should have had EEG. Double check in the raw data. If there was EEG data then rerun preprocessing with hasEEG = True. The beatSpec is wrong. There's dramatic over detection going on between 165 and 170 in the first window. Over detection can also be seen around 3000 in the ECG_beatDetect.jpg figure. Look into why this is happening and see if you can refine the beatSpec to improve. Overall though, the interbeat heart interval and HRV plots still appear reasonable. I believe that the respiration signal is inverted, change rspFlip to +1 and rerun. No macros need to be removed, so macroRemove should be []

250929_Dupi_NMH_GH_3 This session did have EEG. hasEEG should be True. ECG looks good. Needs to be rerun with hasEEG = True

251002_Dupi_NMH_AB_3 This session also needs to be rerun with hasEEG = True. Otherwise looks good. 

251013_Dupi_NMH_JN_3 This session also needs to be rerun with hasEEG = True. No macros need removal, so macroRemove should be []. 

251110_Dupi_NMH_PC_2 This session also needs to be rerun with hasEEG = True. It seems like noisey ECG periods are resulting in a lot of overdetection (e.g. windows 2 and 3 in the examples). Can you try and reduce this by editing the beatSpec. The breathing trace appears inverted, also I think a different rspIDX should be used. Try using rspIDX =1 and rspFlip = 1. 

251120_Dupi_NMH_JL_2 This session also needs to be rerun with hasEEG = True. There's mild over detection going on with the beatSpec. See if this can be corrected. The respiration trace is flipped. It's the correct respiration channel, but try using rspFlip = 1. No macros need removal, so change macroRemove = []. 

260227_EEG_NWU_HW. It appears that cyclic sigh data is being over segmented. This might have to do with the condition list not being read in correctly. Find this participant's raw behavioral data, rerun it through processing to obtain condition labels. If the participant's raw behavioral data can't be found or is corrupted in some way that you can't extract it, then flag this in your next report. This will need to be rerun to correct for the cyclic sigh issue. 

260316_Dupi_NMH_PD_1 has EEG data so hasEEG should be True. There appears to be mild overdetection of heart beats, but it might be fine. Breathing trace is inverted rspFlip should be +1. No macros should be removed, so macroRemove should be []. 

260316_Dupi_NMH_PD_2 has EEG data so hasEEG should be True. No macros should be removed, so macroRemove should be []

260326_OBE_NWU_AD_1 is good

260326_OBE_NWU_AD_2 Something is missing. There should have been at least one more block in which attention to breath focused breathing was recorded. It appears that the photodiode for event detection may not have been plugged in if the event channel is blank. You'll have to do some hard coding in the make out dat script for AD_2. since the psychopy respiration recordings are available for thi ssession located in the CZelano/breathingDataFiles folder, you can reconstruct the time perior of the slowFocus condition and the audiobook condition by matching the respiration signals in the .csv files to those in the .mat files. Establish the timing in scratch code, then hard code the results into the preprocessing of AD_2's data. There may not be affective or mindfulness ratings, so those can be left blank in the final output. In addition, the respiration signal is flipped. Change rspFlip to +1.   

260406_Dupi_NMH_BS_1 This session does have EEG, so hasEEG should be True. The respiration signal is flipped, so rspFlip should be +1. No macros need to be removed so macroRemove should be []. spikeClean should be 1. 

260504_Dupi_NMH_JA_1 has EEG so hasEEG should be True. Respiration signal is flipped, so rspFlip should be +1. No macros need to be removed so macroRemove should be []. spikeClean should be 1. 

260504_Dupi_NMH_JA_2 has EEG so hasEEG should be True. The respiration signal is flipped, so rspFlip should be +1. No macros need to be removed, so macroRemove should be []. spikeClean should be 1. 

260514_OBE_NWU_BW_1 The respiration signal is flipped, so rspFlip should be +1. 

260608_OBE_NWU_RX_1 looks good. 

250225_OBE_NWU_AS_4 double check that there's really no EEG. don't include that excessive number of subject specific figures in future reports. I want to see the ECG and breathing QC figures like for the breathing tasks. 

250904_OBE_NWU_TI_1 if this is an incomplete file, then finish it. You can delete the intermediate and start again from raw. I want to see the ECG and breathing QC figures like for the breathing tasks. 

251009_OBE_NWU_CP_1 Beat detection completely failed despite clear heart beats in the ECG traces. Check the beatSpec and fix it. Breath detection, blink removal, and macros look good. Don't include the excessive number of results figures in future reports on preprocessing. 

260806_EEG_NWU_JH looks good


260806_EEG_NWU_MM looks good

260807_EEG_NWU_GP looks good

260810_EEG_NWU_AL looks good

260810_EEG_NWU_IS we're missing breaths more frequently than I'd like. Can you audit and assess why? For example at 394, 410, 985. 

260811_EEG_NWU_HK Missing breaths at 408, 1004, and 1614. 

260811_EEG_NWU_MS Missing breaths at 430, 1074, 1085. 


260805_EEG_NWU_CA why didn't blink removal run? 

260806_EEG_NWU_JH there are some trough detections in the breathing for example at 1813 and 807. Perhaps we should add a hard rule to the breath detection algorithm that onset cannot occur in the first 20% of the trough to peak interval. 


260806_EEG_NWU_MM looks good. 

260807_EEG_NWU_GP looks good. 

260810_EEG_NWU_AL looks good


260810_EEG_NWU_IS looks good

260811_EEG_NWU_HK looks pretty good, but some trough detection, should be rerun with the new breath detection rule mentioned above. 


 260811_EEG_NWU_MS looks  good. 

250929_Dupi_NMH_GH_1 looks good

251006_OBE_NWU_RY_1 something looks wrong with the ECG signal. See if you can recover it. Maybe try referencing one ECG channel to another, try different combinations to see if a clear heart rhythm pops out then fit a beatSpec to it if you find one. 

251027_Dupi_NMH_DL_1 looks good. 


260105_OBE_NWU_ZF_1 detection of heart beats looks bad in window 1. It may have been thrown off by noise events. There's over detection around the noise and underdetection throughout the rest of the window. See if you can fix this. 


260622_OBE_NWU_RC_1 looks good

260625_OBE_NWU_HM_2  Don't do spike removal, so make spikeClean = 0

260702_OBE_NWU_SP_2 Don't do spike removal, so make spikeClean = 0

260720_OBE_NWU_KA_2 Don't do spike removal, so make spikeClean = 0

260316_Dupi_NMH_PD_2 looks good

260504_Dupi_NMH_JA_2 looks good

260622_OBE_NWU_RC_1 make rspThresh be 4000 and backBuff to 500. I don't need to see it again. Call it curated after those changes and rerun. 

260702_OBE_NWU_SP_2 looks good. 

260720_OBE_NWU_KA_2 raise backBuff to 500 and rspThresh to 4000. I don't need to see ita gain. Call it curated after those changes and rerun. 

260316_Dupi_NMH_PD_2 double check but I think they have EEG, so hasEEG should be True. After you double check that, if there's EEG data available then rerun with hasEEG set to true. 

260504_Dupi_NMH_JA_2 switch to rspIDX =1 and rspFlip = 1. 

260608_OBE_NWU_RX_1 Why didn't blink removal run? This usually indicates a highly noisey EEG signal. If that assumption is confirmed, then you can just report that but no need to actually rerun any preprocessing. 

260625_OBE_NWU_HM_2 looks good

260702_OBE_NWU_SP_2 Why didn't blink removal run? This usually indicates a highly noisey EEG signal. If that assumption is confirmed, then you can just report that but no need to actually rerun any preprocessing. 

260720_OBE_NWU_KA_2 looks good

260504_Dupi_NMH_JA_2 what happened here? Are the raw data missing? Are the behavioral data missing? 

260608_OBE_NWU_RX_1 I think this subject did have EEG, check and rerun if there's EEG with hasEEG = True. 

260702_OBE_NWU_SP_2 check for EEG and rerun with hasEEG = True