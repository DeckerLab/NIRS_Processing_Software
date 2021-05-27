%This script extracts information out of a 'groupResults.mat' which is the result of Homer3 processing.
%Currently it is designed to extract the "beta" values from the results of GLM analysis from each subject run, and
%save the results into a text file.  The script can be easily reconfigured to extract other desired information, as
%required.  
%Tod Flak 26-May-2021 

beta_scale = 1e6;
excludedchannel_or_stim_outputblank = true;

groupresults_filename = 'groupResults.mat'; %look in the current directory
output_filename = 'groupResults.txt';
path = [pwd '\'];  %get current directory

if ~isfile(groupresults_filename)  
    [file,path] = uigetfile({'*.mat',...
             'Matlab data file (*.mat)'},'Select Group Results Matlab data file ...');
   if ~ischar(file) &&  file==0; return; end      
   groupresults_filename = [path file];    
end

response = inputdlg('If desired, change output file name','Output file name',[1 40],{output_filename});
if isempty(response); return; end
output_filename = [path  response{1}];
disp(['Creating file:' output_filename]); 

append_tofile = false;
if isfile(output_filename)
    response = questdlg(sprintf(['The output file already exists.  Do you want to append to that file?\n' ...
                                '(''No'' will overwrite existing file).']), ...
        'Append results?', ...
        'Yes','No','Cancel','Yes');
        if (strcmp(response,'Cancel')); return; end    
        append_tofile = strcmp(response,'Yes');
end

DataGroup = inputdlg('Assign a name to this data group.','Data Group name',[1 40]);
DataGroup = DataGroup{1};

if append_tofile 
    fidOutput = fopen(output_filename,'at');
else
    fidOutput = fopen(output_filename,'wt');
    fprintf(fidOutput,  'DataGroup\tSubject\tRunName\tRunIndex\tCondition\tConditionIndex\tSpecies\tSource\tDetector\tChannel\tBeta_scaled\n');
end

groupdata = load(groupresults_filename);
if isempty(groupdata); error('Selected file has no Matlab objects'); end
if ~isfield(groupdata,'group'); error('Selected file does not contain the expected object ''group''.'); end

groupdata.group.Load; %must call this to populate many of the datafields throughout the object

Hb_species = [{'HbO'},{'HbR'}];  %Note that nowhere is the order of values in the beta array specified as being 
   % 1=HbO and 2=HbR.  We have simply observed that this seems to be the order in the array, so it is hard-coded
   % here.  If there is a source of these names somewhere in the data structure, it should be used instead of this
   % hard-coded order.

for idx_subj=1:length(groupdata.group.subjs)
    this_subj = groupdata.group.subjs(1,idx_subj);
    this_subj.Load;
    subj_name = this_subj.name;
    subj_name= strrep(subj_name,'Subj_','');  %typically the subject name will start with 'Subj_'; if so, strip it off
    disp(['  outputting subject ' subj_name]);
    
    for idx_run=1:length(this_subj.runs)
        this_run = this_subj.runs(1,idx_run);
        this_run.Load;
        if isempty(this_run.procStream.output.misc)
            error(['For subject run ''%s'' the procStream.output.misc is empty.\n' ...
                    'This may indicate that the dataset has not been properly processed.'], this_run.name);
        end
        
        measures = this_run.procStream.output.dod.measurementList;  %get array of all channels (source & detector) in raw data
        measures = findobj(measures,'wavelengthIndex',1);  %keep only the wavelengthIndex 1 channel info
        
        stims = this_run.procStream.output.misc.stim;
        
        beta_4d = this_run.procStream.output.misc.beta{1};  % dimensions: # of basis functions ;  # of Hb Species ; # of channels ; # of conditions
        % check the dimensions to make sure it all makes sense.
        if isempty(beta_4d)  %this indicates the GLM HRF was not computed for this subject.  Warn user, offer to skip
            response = questdlg(sprintf(['For subject run ''%s'' the ''beta'' object is empty.  This may indicate the GLM failed for this subject.\n' ...
                'You can abort processing, or skip the output of this subject run.'], this_run.name), ...
                'Missing GLM betas', ...
                'Skip run','Abort','Skip run');
                if (strcmp(response,'Skip run'))
                    continue; %go to next run
                else
                    return;  %Abort
                end    
        end
        if size(beta_4d,1)~=1
            error(['This script expects there to be only a single basis function reported in the beta structure.  For subject run ''%s'' the first dimension of the beta object is: %d.\n' ...
                    'If you want to process this, you will need to revise the script slightly.'], this_run.name,size(beta_4d,1));
        end
        if size(beta_4d,2)~=2
            error(['This script expects there to be two Hb species (oxyHb and deoxyHb) reported in the beta structure, so the second dimension should be size 2. \n' ... 
                    'For subject run ''%s'' the size of the second dimension of the beta object is: %d.\n' ...
                    'If you want to process this, you will need to revise the script slightly.'], this_run.name,size(beta_4d,2));
        end
        if size(beta_4d,3)~=length(measures)
            error(['This script expects the size of the third dimension of the beta array should be the same as the number of channels. \n' ... 
                    'For subject run ''%s'' the size of the third dimension of the beta object is %d, but the number of channels is %d.\n' ...
                    'If you want to process this, you will need to revise the script slightly.'], this_run.name,size(beta_4d,3), length(measures));
        end
        if size(beta_4d,4)~=length(stims)
            error(['This script expects the size of the fourth dimension of the beta array should be the same as the number of conditions. \n' ... 
                    'For subject run ''%s'' the size of the fourth dimension of the beta object is %d, but the number of conditions is %d.\n' ...
                    'If you want to process this, you will need to revise the script slightly.'], this_run.name,size(beta_4d,4), length(stims));
        end       
        
        %determine if all zeros for some channel or some event -- this indicates an excluded channel, or all stims
        %of an event being excluded.
        perchannel_allzero = squeeze(min(beta_4d==0,[],[1 2 4]));
        perstim_allzero = squeeze(min(beta_4d==0,[],[1 2 3]));

        for idx_species=1:size(beta_4d,2)
            for idx_measure = 1:length(measures)
                this_measure = measures(idx_measure);
                for idx_stim=1:length(stims)
                    this_stim = stims(1,idx_stim);
                        %fprintf(fidOutput, 'Subject\tRunName\tRunIndex\tCondition\tConditionIndex\tSpecies\tSource\tDetector\tChannel\tBeta');
                        
                        if ((perchannel_allzero(idx_measure) || perstim_allzero(idx_stim))  && excludedchannel_or_stim_outputblank)
                            %if the channel was excluded, output a blank for the beta
                            fprintf(fidOutput, '%s\t%s\t%s\t%d\t%s\t%d\t%s\t%d\t%d\t%d\t%f\n', ...
                                   DataGroup, subj_name, this_run.name, this_run.iRun, this_stim.name, idx_stim, Hb_species{idx_species}, ...
                                   this_measure.sourceIndex, this_measure.detectorIndex,idx_measure,'');
                        else
                            fprintf(fidOutput, '%s\t%s\t%s\t%d\t%s\t%d\t%s\t%d\t%d\t%d\t%f\n', ...
                                   DataGroup, subj_name, this_run.name, this_run.iRun, this_stim.name, idx_stim, Hb_species{idx_species}, ...
                                   this_measure.sourceIndex, this_measure.detectorIndex,idx_measure,beta_4d(1,idx_species,idx_measure,idx_stim)*beta_scale);
                        end
                        
                end
            end
        end
        
    end
end

fclose(fidOutput);
disp('file output complete');