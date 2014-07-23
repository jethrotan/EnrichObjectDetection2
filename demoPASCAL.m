VOC_PATH = '/home/chrischoy/Dataset/VOCdevkit/';

addpath('HoG');
addpath('HoG/features');
addpath('Util');
addpath('../MatlabRenderer/');
addpath(VOC_PATH);
addpath([VOC_PATH, 'VOCcode']);


CLASS = 'bicycle';
TYPE = 'val';

azs = 0:30:330; % azs = [azs , azs - 10, azs + 10];
els = [0 20];
fovs = [25];
yaws = ismac * 180 + [-30:30:30];
n_cell_limit = [150];
lambda = [0.02];
% visualize = true;
visualize = false;

model_file = 'Mesh/Bicycle/road_bike';
model_name = strrep(model_file, '/', '_');

detector_name = sprintf('%s_lim_%d_lam_%0.4f_a_%d_e_%d_y_%d_f_%d.mat',...
    model_name, n_cell_limit, lambda, numel(azs), numel(els), numel(yaws), numel(fovs));

if exist(detector_name,'file')
  load(detector_name);
else
  load('Statistics/sumGamma_N1_40_N2_40_sbin_4_nLevel_10_nImg_1601_napoli1_gamma.mat');
  detectors = dwot_make_detectors_slow(mu, Gamma, [model_file '.3ds'], azs, els, yaws, fovs, n_cell_limit, lambda, visualize);
  if sum(cellfun(@(x) isempty(x), detectors))
    error('Detector Not Completed');
  end
  eval(sprintf(['save ' detector_name ' detectors']));
end

templates = cellfun(@(x) x.whow, detectors,'UniformOutput',false);

VOCinit;
param = get_default_params(6, 10, 70);

% load dataset
[gtids,t]=textread(sprintf(VOCopts.imgsetpath,[CLASS '_' TYPE]),'%s %d');

N_IMAGE = length(gtids);

% extract ground truth objects
npos = 0;
tp = cell(1,N_IMAGE);
fp = cell(1,N_IMAGE);
% atp = cell(1,N_IMAGE);
% afp = cell(1,N_IMAGE);
detScore = cell(1,N_IMAGE);
detectorId = cell(1,N_IMAGE);
detIdx = 0;


gt(length(gtids))=struct('BB',[],'diff',[],'det',[]);
for imgIdx=1:N_IMAGE
    imgTic = tic;
    % read annotation
    recs(imgIdx)=PASreadrecord(sprintf(VOCopts.annopath,gtids{imgIdx}));
    
    clsinds = strmatch(CLASS,{recs(imgIdx).objects(:).class},'exact');
    gt(imgIdx).BB=cat(1,recs(imgIdx).objects(clsinds).bbox)';
    gt(imgIdx).diff=[recs(imgIdx).objects(clsinds).difficult];
    gt(imgIdx).det=false(length(clsinds),1);
    
    im = imread([VOCopts.datadir, recs(imgIdx).imgname]);
    [bbsNMS ]= dwot_detect( im, templates, param);
    
    nDet = size(bbsNMS,1);
    tp{imgIdx} = zeros(1,nDet);
    fp{imgIdx} = zeros(1,nDet);
%     atp{imgIdx} = zeros(1,nDet);
%     afp{imgIdx} = zeros(1,nDet);
    detectorId{imgIdx} = bbsNMS(:,11)';
    detScore{imgIdx} = bbsNMS(:,end)';
    
    for bbsIdx = 1:nDet
      ovmax=-inf;
      
      % search over all objects in the image
      for j=1:size(gt(imgIdx).BB,2)
          bbgt=gt(imgIdx).BB(:,j);
          bi=[max(bbsNMS(1),bbgt(1)) ; max(bbsNMS(2),bbgt(2)) ; min(bbsNMS(3),bbgt(3)) ; min(bbsNMS(4),bbgt(4))];
          iw=bi(3)-bi(1)+1;
          ih=bi(4)-bi(2)+1;
          if iw>0 && ih>0                
              % compute overlap as area of intersection / area of union
              ua=(bbsNMS(3)-bbsNMS(1)+1)*(bbsNMS(4)-bbsNMS(2)+1)+...
                 (bbgt(3)-bbgt(1)+1)*(bbgt(4)-bbgt(2)+1)-...
                 iw*ih;
              ov=iw*ih/ua;
              
              if ov > ovmax
                  ovmax = ov;
                  jmax = j;
              end
          end
      end
      
      % assign detection as true positive/don't care/false positive
      if ovmax >= VOCopts.minoverlap
          if ~gt(imgIdx).diff(jmax)
              if ~gt(imgIdx).det(jmax)
                  tp{imgIdx}(bbsIdx)=1;            % true positive
                  gt(imgIdx).det(jmax)=true;
              else
                  fp{imgIdx}(bbsIdx)=1;            % false positive (multiple detection)
              end
          end
      else
          fp{imgIdx}(bbsIdx)=1;                    % false positive
      end
    end
    
    % if visualize
    if 1
      padding = 100;
      paddedIm = uint8(pad_image(im, padding, 255));
      
      for bbsIdx = min(nDet,2):-1:1
        % rectangle('position', bbsNMS(bbsIdx, 1:4) - [0 0 bbsNMS(bbsIdx, 1:2)] + [padding padding 0 0]);
        bnd = round(bbsNMS(bbsIdx, 1:4)) + padding;
        szIm = size(paddedIm);
        clip_bnd = [ min(bnd(1),szIm(2)),...
            min(bnd(2), szIm(1)),...
            min(bnd(3), szIm(2)),...
            min(bnd(4), szIm(1))];
        clip_bnd = [max(clip_bnd(1),1),...
            max(clip_bnd(2),1),...
            max(clip_bnd(3),1),...
            max(clip_bnd(4),1)];
        resizeRendering = imresize(detectors{bbsNMS(bbsIdx, 11)}.rendering, [bnd(4) - bnd(2) + 1, bnd(3) - bnd(1) + 1]);
        resizeRendering = resizeRendering(1:(clip_bnd(4) - clip_bnd(2) + 1), 1:(clip_bnd(3) - clip_bnd(1) + 1), :);
        bndIm = paddedIm( clip_bnd(2):clip_bnd(4), clip_bnd(1):clip_bnd(3), :);
        blendIm = bndIm/2 + resizeRendering/2;
        paddedIm(clip_bnd(2):clip_bnd(4), clip_bnd(1):clip_bnd(3),:) = blendIm;
      end
      imagesc(paddedIm);
      drawnow;
    end
      
    npos=npos+sum(~gt(imgIdx).diff);
    fprintf('%d/%d time : %0.4f\n', imgIdx, N_IMAGE, toc(imgTic));
end

detScore = cell2mat(detScore);
fp = cell2mat(fp);
tp = cell2mat(tp);
% atp = cell2mat(atp);
% afp = cell2mat(afp);
detectorId = cell2mat(detectorId);

[sc, si] =sort(detScore,'descend');
fpSort = cumsum(fp(si));
tpSort = cumsum(tp(si));

% atpSort = cumsum(atp(si));
% afpSort = cumsum(afp(si));

detectorIdSort = detectorId(si);

recall = tpSort/npos;
precision = tpSort./(fpSort + tpSort);

% arecall = atpSort/npos;
% aprecision = atpSort./(afpSort + atpSort);

ap = VOCap(recall', precision');
% aa = VOCap(arecall', aprecision');
fprintf('AP = %.4f\n', ap);
plot(recall, precision, 'r', 'LineWidth',3);
% hold on;
% plot(arecall, aprecision, 'g', 'LineWidth',3);
xlabel('Recall');
% ylabel('Precision/Accuracy');
% tit = sprintf('Average Precision = %.1f / Average Accuracy = %1.1f', 100*ap,100*aa);

tit = sprintf('Average Precision = %.1f', 100*ap);
title(tit);
axis([0 1 0 1]);
set(gcf,'color','w');
saveas(gcf,sprintf('Result/VOC_NCells_%d_lambda_%0.4f_azs_%d_els_%d_fovs_%d_honda_accord.png',...
  n_cell_limit,lambda,numel(azs),numel(els),numel(fovs)));