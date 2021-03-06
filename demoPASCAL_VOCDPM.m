addpath('HoG');
addpath('Util');
addpath('DecorrelateFeature/');
addpath('bin/');
addpath('Visualization/');
addpath('../OSGRenderer/');
addpath('../OSGRenderer/bin');
addpath('../MatlabCUDAConv/');
addpath('3rdParty/SpacePlot');
addpath('3rdParty/MinMaxSelection');
% addpath('Diagnosis');
rng('default');
DATA_SET = 'PASCAL12';
dwot_set_datapath;

COMPUTING_MODE = 1;
CLASS = 'Aeroplane';
SUB_CLASS = [];     % Sub folders
LOWER_CASE_CLASS = lower(CLASS);
TEST_TYPE = 'val';
SAVE_PATH = fullfile('Result',[LOWER_CASE_CLASS '_' TEST_TYPE]);
if ~exist(SAVE_PATH,'dir'); mkdir(SAVE_PATH); end

DEVICE_ID = 0; % 0-base indexing

if COMPUTING_MODE > 0
  gdevice = gpuDevice(DEVICE_ID + 1); % Matlab use 1 base indexing
  reset(gdevice);
  cos(gpuArray(1));
end
daz = 45;
del = 20;
dfov = 10;
dyaw = 10;

azs = 0:7.5:359; % azs = [azs , azs - 10, azs + 10];
els = -30:7.5:30;
fovs = [25];
yaws = 0;
n_cell_limit = [250];
lambda = [0.15];
detection_threshold = 45;

visualize_detection = true;
visualize_detector = false;

sbin = 6;
n_level = 20;
n_max_proposals = inf;
n_max_tuning = 1;
% Load models
[ model_names, model_paths ] = dwot_get_cad_models('Mesh', CLASS, SUB_CLASS, {'3ds','obj'});

% models_to_use = {'bmx_bike',...
%               'fixed_gear_road_bike',...
%               'glx_bike',...
%               'road_bike'};

% models_to_use = {'atx_bike',...
%               'atx_bike_rot',...
%               'bmx_bike_2',...
%               'bmx_bike_4',...
%               'chopper_bike',...
%               'brooklyn_machine_works_bike',...
%               'downhill_bike',...
%               'glx_bike',...
%               'road_bike',...
%               'uncategorized_bike',...
%               'road_bike_rot'};
          
% models_to_use = {'2012-VW-beetle-turbo',...
%               'Kia_Spectra5_2006',...
%               '2008-Jeep-Cherokee',...
%               'Ford Ranger Updated',...
%               'BMW_X1_2013',...
%               'Honda_Accord_Coupe_2009',...
%               'Porsche_911',...
%               '2009 Toyota Cargo'};

% models_to_use = {'2012-VW-beetle-turbo',...
%             'Peugeot-207',...
%             'Scion_xB',...
%             '2007-Nissan-Versa-_-Tiida-SL',...
%             '2010-Chevrolet-Aveo5-LT',...
%             '2012-Citroen-DS4',...
%             'Kia_Spectra5_2006',...
%             'Opel-Meriva',...
%             'NM07',...
%             'Portugal_Racing_Junior',...
%             '2008-Jeep-Cherokee',...
%             '2012-Mercedes-Benz-M-Class',...
%             'BMW_X1_2013',...
%             'Benz_SL500_roofdown_2013',...
%             'Chevrolet Camaro',...
%             'Honda-Accord-3',...
%             'Honda_Accord_Coupe_2009',...
%             'Mercedes-Benz-C63-2012',...
%             'Nissan-Maxima_2009',...
%             'Porsche_911_wing_2014',...
%             '2001-2004 Ford Ranger Edge',...
%             '2013-Ford-F150-Eco-Boost-King-Ranch-4X4-Crew-Cab',...
%             'Ford Ranger Updated',...
%             '2002 Dodge Ram FedEx',...
%             '2009 Toyota Cargo',...
%             'Maserati-3500GT',...
%             'Skylark_Cruiser_1971'};

% models_to_use = {'Honda-Accord-3'};
% 
% use_idx = ismember(model_names,models_to_use);
% 
% model_names = model_names(use_idx);
% model_paths = model_paths(use_idx);

% model_names = model_names(1:30)
% model_paths = model_paths(1:30)

% skip_criteria = {'empty', 'truncated','difficult'};
skip_criteria = {'none'};
skip_name = cellfun(@(x) x(1), skip_criteria);

%%%%%%%%%%%%%%% Set Parameters %%%%%%%%%%%%
dwot_get_default_params;

param.template_initialization_mode = 0; 
param.nms_threshold = 0.3;
param.model_paths = model_paths;

param.b_calibrate = 0;      % apply callibration if > 0
param.n_calibration_images = 100;
param.calibration_mode = 'gaussian';

param.detection_threshold = 40;
param.image_scale_factor = 1; % scale image accordingly and detect on the scaled image

% Tuning mode == 'none', no tuning
%             == 'mcm', MCMC
%             == 'not supported yet', Breadth first search
%             == 'bfgs', Quasi-Newton method (BFGS)
param.proposal_tuning_mode = 'mcmc';

% Detection mode == 'dwot' ours
%                == 'cnn'
%                == 'dpm'
%                == 'gt' ground truth
param.detection_mode = 'cnn';
param.proposal_score_threshold = -0.7;

% Padding ratio applied on the proposal region
param.extraction_padding_ratio = 0.2;

% Save mode = 'd' detections
%           = 'dt' detection and template index
%           = 'dv' detection and viewpoint
%           = 'dtp' detection template index and proposal
%           = 'dtpv' detection template index and proposal
%           = 'dvpv' detection template index and proposal
%           = 'dvp' detection viewpoint and proposal
param.detection_save_mode = 'dv';
param.proposal_dwot_save_mode = 'dtpv';
param.tuning_save_mode = 'dvpv';
param.export_figure = true;

% image_region_extraction.padding_ratio = 0.2;
param.PASCAL3D_ANNOTATION_PATH = PASCAL3D_ANNOTATION_PATH;
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
param.n_views = 8;
param = dwot_put_color_range_and_map(param);

% detector name
[ detector_model_name ] = dwot_get_detector_name( model_names, param);
detector_name = sprintf('%s_%s_lim_%d_lam_%0.4f_a_%d_e_%d_y_%d_f_%d',...
            LOWER_CASE_CLASS,  detector_model_name, n_cell_limit, lambda,...
            numel(azs), numel(els), numel(yaws), numel(fovs));

detector_file_name = sprintf('%s.mat', detector_name);

%% Make empty detection save file
% if ~strcmp(param.detection_mode,'dwot')

[detection_result_file, detection_result_common_name, file_temp_idx] = ...
    dwot_get_detection_result_file_name(DATA_SET, TEST_TYPE, SAVE_PATH, model_names,...
        param.detection_save_mode, server_id, param, sprintf('prop_%s_nv_%d', param.detection_mode,param.n_views), true);
fprintf('%s\n',detection_result_file);
    
[detection_dwot_proposal_result_file] = ...
    dwot_get_detection_result_file_name(DATA_SET, TEST_TYPE, SAVE_PATH, model_names,...
        param.proposal_dwot_save_mode, server_id, param, sprintf('prop_%s_dwot_nv_%d', param.detection_mode, param.n_views), true, file_temp_idx);
fprintf('%s\n',detection_dwot_proposal_result_file);

if ~strcmp(param.proposal_tuning_mode,'none')
    [detection_tuning_result_file, detection_tuning_result_common_name] = ...
        dwot_get_detection_result_file_name(DATA_SET, TEST_TYPE, SAVE_PATH, model_names,...
            param.tuning_save_mode, server_id, param, sprintf('prop_%s_tuning_nv_%d', param.detection_mode, param.n_views), true, file_temp_idx);
     fprintf('%s\n',detection_tuning_result_file);
end

%% Make Renderer
if ~strcmp(param.proposal_tuning_mode, 'none') || ~exist('renderer','var') || ~exist(detector_file_name,'file')
    % Initialize renderer
    renderer = Renderer();
    if ~renderer.initialize(model_paths, 700, 700)
        error('fail to load model');
    end
end

%% Make Detectors
if exist(detector_file_name,'file')
    load(detector_file_name);
else
    [detectors] = dwot_make_detectors_grid(renderer, azs, els, yaws, fovs, 1:length(model_names),...
        LOWER_CASE_CLASS, param, visualize_detector);
    [detectors, detector_table]= dwot_make_table_from_detectors(detectors);
    if sum(cellfun(@(x) isempty(x), detectors))
      error('Detector Not Completed');
    end
    eval(sprintf(['save -v7.3 ' detector_file_name ' detectors detector_table']));
    % detectors = dwot_make_detectors(renderer, azs, els, yaws, fovs, param, visualize_detector);
    % eval(sprintf(['save ' detector_name ' detectors']));
end

%%%%% For Debugging
param.detectors              = detectors;
param.detect_pyramid_padding = 10;
%%%%%%%%%%%%

%% Make templates, these are just pointers to the templates in the detectors,
% The following code copies variables to GPU or make pointers to memory
% according to the computing mode.
%
% The GPU templates accelerates the computation time since it is already loaded
% on GPU.
if COMPUTING_MODE == 0
    % for CPU convolution, use fconvblas which handles template inversion
    templates_cpu = cellfun(@(x) single(x.whow), detectors,'UniformOutput',false);
elseif COMPUTING_MODE == 1
    % for GPU convolution, we use FFT based convolution. invert template
    templates_gpu = cellfun(@(x) gpuArray(single(x.whow(end:-1:1,end:-1:1,:))), detectors,'UniformOutput',false);
elseif COMPUTING_MODE == 2
    templates_gpu = cellfun(@(x) gpuArray(single(x.whow(end:-1:1,end:-1:1,:))), detectors,'UniformOutput',false);
    templates_cpu = cellfun(@(x) single(x.whow), detectors,'UniformOutput',false);
else
    error('Computing mode undefined');
end

template_size = cell2mat(cellfun(@(x) (x.sz)', detectors,'uniformoutput',false));
max_template_size = max(template_size, [],2);
min_template_size = min(template_size, [],2);

%% Load CNN Proposals
switch param.detection_mode
    case 'vocdpm'
        vocdpm_result = load(fullfile(VOC_DPM_PATH, sprintf('%s_vp%02d.mat',LOWER_CASE_CLASS, param.n_views)));
        % cnn_class_idx = find(strcmp(LOWER_CASE_CLASS, cnn_detection.classes));
    case 'cnn'
        if ~exist('cnn_detection','var')
            cnn_detection = load('3dpascal_pascal12val_rcnn_detections');
            cnn_class_idx = find(strcmp(LOWER_CASE_CLASS, cnn_detection.classes));
        end
end

[gtids,t] = textread(sprintf(VOCopts.imgsetpath,[LOWER_CASE_CLASS '_' TEST_TYPE]),'%s %d');

N_IMAGE = min(length(gtids), inf);

gt = struct('BB',[],'diff',[],'det',[]);

for img_idx=1:N_IMAGE
    imgTic = tic;
    fprintf('%d/%d',img_idx,N_IMAGE);
    % Find file name
%     img_file_name = regexp(cnn_detection.imgFilePaths{img_idx}, '\/(?<img>\w+)\.png','names');
%     img_file_name = img_file_name.img;

    % read annotation
    img_file_name = gtids{img_idx};
    recs = PASreadrecord(sprintf(VOCopts.annopath, img_file_name));
    
    % Read 3D viewpoint annotation
    clsinds = find(strcmp(LOWER_CASE_CLASS, {recs.objects(:).class}));

    [skip_img, object_idx] = dwot_skip_criteria(recs.objects(clsinds), skip_criteria);
    
    if skip_img; fprintf('skipping\n'); continue; end;
    
    clsinds = clsinds(object_idx);
  
    %% Proposal region
    im = imread([VOCopts.datadir, recs.imgname]);
    im = imresize(im, param.image_scale_factor);
    im_size = size(im);
    
    switch param.detection_mode
      case 'dwot'
        if COMPUTING_MODE == 0
          [formatted_bounding_box] = dwot_detect( im, templates_cpu, param);
        elseif COMPUTING_MODE == 1
          [formatted_bounding_box] = dwot_detect_gpu( im, templates_gpu, param);
        end
        fprintf('convolution time: %0.4f\n', toc(imgTic));
      case 'cnn'
        bounding_box_proposals = cnn_detection.detBoxes{cnn_class_idx}{img_idx};
        % bounding_box_proposals = bounding_box_proposals((bounding_box_proposals(:,end) > -inf ),:);
        if isempty(bounding_box_proposals)
            bounding_box_proposals = [0 0 0 0 -inf];
        end
        prediction_box = param.image_scale_factor * bounding_box_proposals(:,1:4);
        prediction_score = bounding_box_proposals(:,end);
        formatted_bounding_box = zeros(size(bounding_box_proposals,1),12);
        formatted_bounding_box(:,end) = bounding_box_proposals(:,end);
        formatted_bounding_box(:,1:4) = param.image_scale_factor * double(bounding_box_proposals(:,1:4));
      case 'vocdpm'
        detection_struct = vocdpm_result.res(img_idx).detections;
        formatted_bounding_box = zeros(numel(detection_struct), 12);
        formatted_bounding_box(:,1:4) = param.image_scale_factor * double(cell2mat({detection_struct.bb}'));
        formatted_bounding_box(:,10) = cell2mat({detection_struct.vp}');
        formatted_bounding_box(:,12) =  cell2mat({detection_struct.score})';
      case 'dpm'
        error('NOT SUPPORTED');
      case 'gt'
        load()
    end 
   
    % Automatically sort them according to the score and apply NMS
    proposal_formatted_bounding_boxes = esvm_nms(formatted_bounding_box, 0.7);
    ground_truth_bounding_boxes = param.image_scale_factor * cat(1, recs.objects(clsinds).bbox);
    % prediction_azimuth = proposal_formatted_bounding_boxes(:,10);

    [null_padded_box , skip_current_image] = dwot_return_null_padded_box(proposal_formatted_bounding_boxes, [], 12);
    proposal_save_structure = dwot_formatted_bounding_boxes_to_save_structure(null_padded_box);
    dwot_save_detection(SAVE_PATH, detection_result_file, false, ...
            param.detection_save_mode, proposal_save_structure, img_file_name); 
    
    % For proposal_dwot and tuning results, add proposals that were
    % truncated due to thresholding
    valid_proposal_indexes = (proposal_formatted_bounding_boxes(:,end) > param.proposal_score_threshold);
    [null_padded_below_thresh_box , ~] = dwot_return_null_padded_box(proposal_formatted_bounding_boxes(~valid_proposal_indexes,:), [], 12);
    null_box = zeros(size(null_padded_below_thresh_box,1),12); null_box(:,end) = -inf;
    proposal_dwot_save_structure = dwot_formatted_bounding_boxes_to_save_structure(...
                null_box, null_padded_below_thresh_box);
    
	dwot_save_detection(SAVE_PATH, detection_dwot_proposal_result_file, false,...
            param.proposal_dwot_save_mode, proposal_dwot_save_structure, img_file_name);
    dwot_save_detection(SAVE_PATH, detection_tuning_result_file, false, ...
            param.tuning_save_mode, proposal_dwot_save_structure, img_file_name); 

    if skip_current_image; continue; end;
    
    %% Visualize proposal detections
    if visualize_detection && strcmp( param.detection_mode, 'dwot')
        dwot_visualize_predictions_in_quadrants(im, proposal_formatted_bounding_boxes,...
                            ground_truth_bounding_boxes, detectors, param);drawnow;
    else
        clf
        imagesc(im); axis equal; axis tight; axis off;
        dwot_visualize_bounding_boxes(proposal_formatted_bounding_boxes(valid_proposal_indexes,1:4),...
                    proposal_formatted_bounding_boxes(valid_proposal_indexes,end),...
                    's:%0.2f', proposal_formatted_bounding_boxes(valid_proposal_indexes,end), param.color_range, param.color_map);drawnow;
    end
    
    if visualize_detection && param.export_figure && numel(ground_truth_bounding_boxes) > 0
        save_name = sprintf(['%s_img_%d.jpg'], detection_result_common_name, img_idx);
        print('-djpeg','-r150',fullfile(SAVE_PATH, save_name));
    end
    
    %% Proposal Detection
    n_proposals = min([n_max_proposals, size(proposal_formatted_bounding_boxes,1), ...
        nnz(proposal_formatted_bounding_boxes(:,end) > param.proposal_score_threshold)]);
    proposal_dwot_time = tic;
    % For each proposals draw original, before and after
    for proposal_idx = 1:n_proposals
	  %% Extrac region
        current_proposal_formatted_box = proposal_formatted_bounding_boxes(proposal_idx, :);
        [proposal_im, clip_padded_bbox, clip_padded_bbox_offset, width, height] =...
                dwot_extract_image_with_padding(im, current_proposal_formatted_box,...
                param.extraction_padding_ratio, im_size);
        if isempty(proposal_im); continue; end;
        
      %% Find right scale to search. Resize image if it's too small
        search_scale = max_template_size(1:2)' * sbin ./ [height width];
        proposal_resize_scale = 1;
        if max(search_scale) >= 0.7
            proposal_resize_scale = max(search_scale) * 1.6;
            proposal_im = imresize(proposal_im, proposal_resize_scale);
            search_scale = search_scale ./ proposal_resize_scale;
        end
        param.detect_min_scale = min(1, min(search_scale) / 1.4);
        param.detect_max_scale = min(1, min(search_scale) * 1.4);

        % Detect object and get initial proposal regions
        [proposal_dwot_formatted_boxes, hog, scales] = dwot_detect_gpu( proposal_im, templates_gpu, param);
        
        % Add null detection incase it does not have any detections
        [proposal_dwot_formatted_boxes , skip_current_image] = dwot_return_null_padded_box(...
                esvm_nms(proposal_dwot_formatted_boxes, 0.7), [], 12);
        
        % Use top detection
        proposal_dwot_formatted_boxes = proposal_dwot_formatted_boxes(1,:);
        
        % Restore original image coordinate
        proposal_dwot_formatted_boxes_crop_coord = proposal_dwot_formatted_boxes;
        proposal_dwot_formatted_boxes(:,1:4) = bsxfun(@plus, ...
                proposal_dwot_formatted_boxes(:,1:4)/proposal_resize_scale, clip_padded_bbox_offset);
            
        % Save the result on the detection result file
        proposal_dwot_save_structure = dwot_formatted_bounding_boxes_to_save_structure(...
                proposal_dwot_formatted_boxes(1,:), proposal_formatted_bounding_boxes(proposal_idx,:));
        dwot_save_detection(SAVE_PATH, detection_dwot_proposal_result_file, false, param.proposal_dwot_save_mode, ...
                proposal_dwot_save_structure, img_file_name); % save mode != 0 to save template index
        if skip_current_image; 
            dwot_save_detection(SAVE_PATH, detection_tuning_result_file, false, ...
                param.tuning_save_mode, proposal_dwot_save_structure, img_file_name);
            continue; 
        end;

        % For each proposals draw original, before and after
        if visualize_detection 
            clf;
            [proposal_box, proposal_score, ~] = dwot_formatted_bounding_boxes_to_predictions(...
                                                             proposal_formatted_bounding_boxes(proposal_idx,:));
            [prediction_box, prediction_score, prediction_template_index] = dwot_formatted_bounding_boxes_to_predictions(...
                                                              proposal_dwot_formatted_boxes(1,:));
            current_proposal_detector = detectors{prediction_template_index};

            overlay_im = dwot_draw_overlay_rendering(im, prediction_box, ...
                current_proposal_detector.rendering_image, current_proposal_detector.rendering_depth, [0.8 0.2]);
            imagesc(overlay_im); axis equal; axis tight; axis off;
            dwot_visualize_bounding_boxes(proposal_box, proposal_score, 'prop s:%0.2f',...
                    proposal_score, param.color_range, param.color_map);
            dwot_visualize_bounding_boxes(prediction_box, prediction_score, 'pred s:%0.2f',...
                    prediction_score, param.color_range, param.color_map);
            drawnow;
            if param.export_figure && numel(ground_truth_bounding_boxes) > 0
                save_name = sprintf(['%s_img_%d_dwot_obj_%d.jpg'],...
                      detection_tuning_result_common_name, img_idx,...
                      proposal_idx);
                print('-djpeg','-r150',fullfile(SAVE_PATH, save_name));
            end
        end
        
        
       %% MCMC
         [hog_region_pyramids, im_regions] = dwot_extract_hog(hog, scales, detectors, ...
                              proposal_dwot_formatted_boxes_crop_coord, param, proposal_im);
                          
        tuningTic = tic;
        [best_proposal] = dwot_mcmc_proposal_region(renderer, hog_region_pyramids, im_regions,...
                                        detectors, param, proposal_im, false);
        fprintf(' tuning time : %0.4f\n', toc(tuningTic));

        [tuned_prediction_box, tuned_prediction_score, tuned_prediction_azimuth,...
            tuned_prediction_elevation, tuned_prediction_yaw, tuned_prediction_fov,...
            tuned_prediction_rendering, tuned_prediction_depth] = dwot_extract_proposals(best_proposal);

        tuned_prediction_box(:,1:4) = bsxfun(@plus, ...
                tuned_prediction_box(:,1:4)/proposal_resize_scale, clip_padded_bbox_offset);

        tuned_formatted_bounding_boxes = dwot_predictions_to_formatted_bounding_boxes( tuned_prediction_box,...
                                               tuned_prediction_score, [], [], tuned_prediction_azimuth);
 
        % For each proposals draw original, before and after
        if visualize_detection 
            clf;
            [proposal_box, proposal_score, proposal_template_index] = dwot_formatted_bounding_boxes_to_predictions(...
                                                             proposal_dwot_formatted_boxes);
            current_proposal_detector = detectors{proposal_template_index};

            dwot_visualize_proposal_tuning(im,...
                     proposal_box(1, :), proposal_score(1),...
                     current_proposal_detector.rendering_image, current_proposal_detector.rendering_depth,...
                     tuned_prediction_box(1,:), tuned_prediction_score(1),...
                     tuned_prediction_rendering{1}, tuned_prediction_depth{1},...
                     ground_truth_bounding_boxes, param);
            if param.export_figure && numel(ground_truth_bounding_boxes) > 0
                save_name = sprintf(['%s_img_%d_tuning_%s_obj_%d.jpg'],...
                      detection_tuning_result_common_name, img_idx, param.proposal_tuning_mode,...
                      proposal_idx);
                print('-djpeg','-r100',fullfile(SAVE_PATH, save_name));
            end
        end
        
        save_tuned_structure = dwot_formatted_bounding_boxes_to_save_structure(...
            tuned_formatted_bounding_boxes, proposal_formatted_bounding_boxes(proposal_idx,:));
        dwot_save_detection(SAVE_PATH, detection_tuning_result_file, false, ...
            param.tuning_save_mode, save_tuned_structure, img_file_name); % save mode != 0 to save template index
    end
    
    fprintf(' tuning time : %0.4f\n', toc(proposal_dwot_time));
end

close all;  % space plot casues problem when using different subplot grid

%% Vary NMS threshold
% for n_view = [4,8,16,24]
%     dwot_analyze_and_visualize_cnn_results( fullfile('Result/car_val', 'PASCAL12_car_val_init_0_Car_each_27_lim_250_lam_0.1500_a_24_e_3_y_1_f_1_scale_2.00_sbin_6_level_20_nms_0.30_server_104_cnn_proposal_dwot_tmp_2.txt') , detectors, '/home/chrischoy/DWOT_CNN5', VOCopts, param, skip_criteria, param.color_range, param.nms_threshold, false, n_view, -1, 0);
%     print('-dpng','-r200',fullfile(SAVE_PATH, ['AP_PASCAL12_car_val_init_0_Car_each_27_lim_250_lam_0.1500_a_24_e_3_y_1_f_1_scale_2.00_sbin_6_level_20_nms_0.30_server_104_cnn_proposal_dwot_tmp_2_nms_' sprintf('%0.2f',param.nms_threshold) '_nview_' num2str(n_view) '.png' ] ));
% end
nms_thresholds = 0.3:0.1:0.5;
ap = zeros(numel(nms_thresholds),1);
ap_dwot_prop = zeros(numel(nms_thresholds),1);
ap_save_names = cell(numel(nms_thresholds),1);
ap_tuning_save_name =cell(numel(nms_thresholds),1);
ap_detection_save_names = cell(numel(nms_thresholds),1);
fprintf('Detection of proposals\n');
close all;
for i = 1:numel(nms_thresholds)
    nms_threshold = nms_thresholds(i);
    clf;
    ap(i) = dwot_analyze_and_visualize_vocdpm_results(fullfile(SAVE_PATH, detection_result_file), ...
                        detectors, VOCopts, param, nms_threshold, 'predboxpredview', false);

    ap_save_names{i} = sprintf(['AP_%s_nms_%0.2f.png'],...
                        detection_result_common_name, nms_threshold);

     print('-dpng','-r150',fullfile(SAVE_PATH, ap_save_names{i}));
end

% Detection for regions before tuning
n_views = [4, 8, 16, 24];
score_thresholds = [45];
% n_views = param.n_views;
count = 1;
fprintf('AVP of proposal + ours\n');
for score_threshold = score_thresholds
    for view_idx = 1:numel(n_views)
        for i = 1:numel(nms_thresholds)
            nms_threshold = nms_thresholds(i);
            clf;
            ap_dwot_prop(count) = dwot_analyze_and_visualize_vocdpm_results(fullfile(SAVE_PATH,detection_dwot_proposal_result_file), ...
                                detectors, VOCopts, param, nms_threshold, 'propboxpredviewthres', false, [], n_views(view_idx), -1 ,0, score_threshold);
    
            ap_detection_save_names{count} = sprintf(['AP_%s_proposal_dwot_nms_%0.2f_nview_%d_thres_%d.png'],...
                                detection_result_common_name, nms_threshold, n_views(view_idx), score_threshold);
    
             print('-dpng','-r150',fullfile(SAVE_PATH, ap_detection_save_names{count}));
             count = count + 1;
        end
    end
end

% if ~exist('/scratch/chrischoy/Result/','dir'); mkdir('/scratch/chrischoy/Result/'); end
% save_path = ['/scratch/chrischoy/Result/' detection_result_common_name];
% [~ ,max_nms_idx] = max(ap);
% dwot_analyze_and_visualize_cnn_results(fullfile(SAVE_PATH, detection_result_file), ...
%                         detectors, VOCopts, param, nms_thresholds(max_nms_idx), true, save_path);

if ~strcmp(param.proposal_tuning_mode,'none')
    fprintf('AVP of proposal + ours + MCMC\n');
    count = 1;
    for score_threshold = score_thresholds
        for view_idx = 1:numel(n_views)
            for i = 1:numel(nms_thresholds)
                nms_threshold = nms_thresholds(i);
                clf;
                ap_tuning(count) = dwot_analyze_and_visualize_vocdpm_results(fullfile(SAVE_PATH,detection_tuning_result_file), ...
                                    detectors, VOCopts, param, nms_threshold, 'propboxpredviewthres', false, [], n_views(view_idx), -1 ,0, detection_threshold);

                ap_tuning_save_name{count} = sprintf(['AP_%s_tuning_%s_nms_%.2f_nview_%d_thres_%d.png'],...
                                    detection_result_common_name, param.proposal_tuning_mode,...
                                    nms_threshold, n_views(view_idx), score_threshold);

                 print('-dpng','-r150',fullfile(SAVE_PATH, ap_tuning_save_name{count}));
                 count = count + 1;
            end
        end
    end
end

% If it runs on server copy to host
% if ~isempty(server_id) && ~strcmp(server_id.num,'capri7')
%     count = 1;
%     for i = 1:numel(nms_thresholds)
%         system(['scp ', fullfile(SAVE_PATH, ap_save_names{i}),...
%             ' @capri7:/home/chrischoy/Dropbox/Research/DetectionWoTraining/',...
%             SAVE_PATH]);
%         for view_idx = 1:numel(n_views)
%             system(['scp ', fullfile(SAVE_PATH, ap_detection_save_names{count}),...
%                 ' @capri7:/home/chrischoy/Dropbox/Research/DetectionWoTraining/',...
%                 SAVE_PATH]);
%             count = count + 1;
%         end
%     end
%     system(['scp ' fullfile(SAVE_PATH, detection_result_file),...
%         ' @capri7:/home/chrischoy/Dropbox/Research/DetectionWoTraining/' SAVE_PATH]);
%     
%     system(['scp ' fullfile(SAVE_PATH, detection_dwot_proposal_result_file),...
%         ' @capri7:/home/chrischoy/Dropbox/Research/DetectionWoTraining/' SAVE_PATH]);
%     
%     if ~strcmp(param.proposal_tuning_mode,'none')
%         system(['scp ', fullfile(SAVE_PATH, ap_tuning_save_name),...
%             ' @capri7:/home/chrischoy/Dropbox/Research/DetectionWoTraining/',...
%             SAVE_PATH]);
%         system(['scp ' fullfile(SAVE_PATH, detection_tuning_result_file),...
%             ' @capri7:/home/chrischoy/Dropbox/Research/DetectionWoTraining/',...
%             SAVE_PATH]);
%     end
% end
