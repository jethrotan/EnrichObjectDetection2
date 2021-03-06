function [bbsNMS, hog, scales, voting_planes] = dwot_detect_voting(I, templates, param)

doubleIm = im2double(I);
image_size = size(I);
[hog, scales] = esvm_pyramid(doubleIm, param);
hogPadder = param.detect_pyramid_padding;
sbin = param.sbin;

nTemplates =  numel(templates);
sz = cellfun(@(x) size(x), templates, 'UniformOutput',false);

minsizes = cellfun(@(x)min([size(x,1) size(x,2)]), hog);
hog = hog(minsizes >= hogPadder*2);
scales = scales(minsizes >= hogPadder*2);
bbsAll = cell(length(hog),1);

% Voting planes
voting_planes = zeros(ceil(image_size(1)/sbin), ceil(image_size(2)/sbin), nTemplates );


for level = length(hog):-1:1
  hog{level} = padarray(single(hog{level}), [hogPadder hogPadder 0], 0); % Convolution, same size
  HM = fconvblasfloat(hog{level}, templates, 1, nTemplates);

%      for modelIdx = 1:nTemplates
%        HM{modelIdx} = convnc(t.hog{level},flipTemplates{modelIdx},'valid');
%      end

  rmsizes = cellfun(@(x) size(x), HM, 'UniformOutput',false);
  scale = scales(level);
  templateIdxes = find(cellfun(@(x) prod(x), rmsizes));
  bbsTemplate = cell(nTemplates,1);
  
  for templateIdx = templateIdxes
    [idx] = find(HM{templateIdx}(:) > param.detection_threshold);
    if isempty(idx)
      continue;
    end

    [y_coord,x_coord] = ind2sub(rmsizes{templateIdx}(1:2), idx);

    [y1, x1] = dwot_hog_to_img_conv(y_coord, x_coord, sbin, scale, hogPadder);
    [y2, x2] = dwot_hog_to_img_conv(y_coord + sz{templateIdx}(1), x_coord + sz{templateIdx}(2), sbin, scale, hogPadder);
    
    for detection_index = 1:numel(idx)
      cliped_bbox = clip_to_image([x1(detection_index),...
                                           y1(detection_index),...
                                           x2(detection_index),...
                                           y2(detection_index)],...
                                           [1, 1, image_size(2), image_size(1)]);
      cx1 = ceil(cliped_bbox(1)/sbin);    cy1 = ceil(cliped_bbox(2)/sbin);    cx2 = floor(cliped_bbox(3)/sbin);    cy2 = floor(cliped_bbox(4)/sbin);
      voting_planes(cy1:cy2,cx1:cx2,templateIdx) = voting_planes(cy1:cy2,cx1:cx2,templateIdx) + (HM{templateIdx}(idx(detection_index))- param.detection_threshold);
    end
    bbs = zeros(numel(y_coord), 12);
    bbs(:,1:4) = [x1 y1, x2, y2];
    
%     o = [uus vvs] - hogPadder;
% 
%     bbs = ([o(:,2) o(:,1) o(:,2)+sz{templateIdx}(2) ...
%                o(:,1)+sz{templateIdx}(1)] - 1) * ...
%              sbin/scale + 1 + repmat([0 0 -1 -1],...
%               length(uus),1);
%     bbs(:,5:12) = 0;

    bbs(:,5) = scale;
    bbs(:,6) = level;
    bbs(:,7) = y_coord;
    bbs(:,8) = x_coord;

    % bbs(:,9) is designated for overlap
    % bbs(:,10) is designated for viewpoint
    
    % bbs(:,9) = boxoverlap(bbs, annotation.bbox + [0 0 annotation.bbox(1:2)]);
    % bbs(:,10) = abs(detectors{templateIdx}.az - azGT) < 30;

    bbs(:,11) = templateIdx;
    bbs(:,12) = HM{templateIdx}(idx);
    bbsTemplate{templateIdx} = bbs;
    
    % if visualize
    if 0
      subplot(131);
      imagesc(I);
      subplot(132);
      imagesc(param.detectors{templateIdx}.rendering);
      subplot(133);
      imagesc(voting_planes(:,:,templateIdx));
      colorbar;
      drawnow;
    end
  end
  bbsAll{level} = cell2mat(bbsTemplate);
end

bbsNMS = esvm_nms(cell2mat(bbsAll),0.5);