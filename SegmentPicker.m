function SegmentPicker(DEM,FD,A,S,basin_num,varargin)
	% Function to select a segment of a stream network from the top of the stream, and plot the long profile 
	% 	and chi-Z relationship of that segment,also outputs the extraced portion of the stream network and chi structure 
	% 	(out of 'chiplot'). Allows user to iteratively select different parts of the stream network and display. 
	% 	Keeps running dataset of all the streams you pick and accept.
	%
	% Required Inputs:
	%	DEM - Digital Elevation as a GRIDobj, assumes unconditioned DEM (e.g. DEMoc from ProcessRiverBasins)
	%	FD - Flow direction as FLOWobj
	%	A - Flow accumulation GRIDobj
	%	S - Stream network as STREAMobj
	%	basin_num - basin number from process river basins for output name or other identifying number for the set of streams you will pick
	%
	% Optional Inputs
	%	conditioned_DEM [] - option to provide a hydrologically conditioned DEM for use in this function (do not provide a conditoned DEM
	%		for the main required DEM input!) which will be used for extracting elevations. See 'ConditionDEM' function for options for making a 
	%		hydrological conditioned DEM. If no input is provided the code defaults to using the mincosthydrocon function.
	%	direction ['down'] - expects either 'up' or 'down', default is 'down', if 'up' assumes individual selections are points above
	%		which you wish to extract and view stream profiles (i.e. a pour point), if 'down' assumes individual
	%		selections are channel heads if specific streams you wish to extract and view stream profiles. 
	%	method ['new_picks'] - expects either 'new_picks' or 'prev_picks', default is 'new_picks' if no input is provided. If 'prev_picks' is
	%			 given, the user must also supply an input for the 'picks' input (see below)
	%	plot_style ['refresh'] - expects either 'refresh' or 'keep', default is 'refresh' if no input is provided. If 'refresh' is given, the plots reset
	%			after each new stream pick, but if 'keep' is given, all selected streams remain on both the map (as thick red lines) and the
	%			chi-z/longitudinal profile/slope-area plots.
	%	plot_type ['vector'] - expects either 'vector' or 'grid', default is 'vector'. Controls whether all streams are drawn as individual lines ('vector') or if
	%		   the stream network is plotted as a grid and downsampled ('grid'). The 'grid' option is much faster with large datasets, 
	%			but can result in inaccurate choices. The 'vector' option is easier to see, but can be very slow to load and interact with.
	%	complete_networks_only [false] - if true, the code will filter out portions of the stream network that are incomplete prior to choosing
	%			streams
	%	picks - expects a m x 3 matrix with columns as an identifying number, x coordinates, and y coordinates OR the name of a point shapefile with a single value column of 
	%			identifying numbers. Will interpret this input as a list of channel heads if 'direction' is 'down' and a list of channel outlets if 'direction' is 'up'.
	%	ref_concavity [0.50] - reference concavity for calculating Chi-Z, default is 0.50
	%	min_elev [] - minimum elevation below which the code stops extracting channel information, only used if 'direction'
	%			   is 'down'
	%	max_area [] - maximum drainage area above which the code stops extracting channel information, only used if 'direction'
	%			   is 'down'
	%	recalc [false] - only valid if either min_elev or max_area are specified. If recalc is false (default) then extraction of 
	%			 streams stops downstream of the condition specified in either min_elev or max_area, but chi is not recalculated 
	%			 and distances will remain tied to the original stream (i.e. distances from the outlet will be relative to the outlet
	%			 of the stream if it continued to the edge of the DEM, not where it stops extracting the stream profile). If recalc is true, 
	%	     	 then chi and distance are recalculated (i.e. the outlet as determined by the min_elev or max_area condition
	%			 will have a chi value of zero and a distance from mouth value of zero).
	%	threshold_area [1e6] - used to redraw downsampled stream network if 'plot_type' is set to 'grid'
	%	interp_value [0.1] - value (between 0 and 1) used for interpolation parameter in mincosthydrocon (not used if user provides a conditioned DEM)
	%
	% Outputs:
	%	Saves an output called 'PickedSegements_*.mat' with the provided basin number containing these results:
	%		StreamSgmnts - Cell array of selected stream segments as STREAMobj
	%		ChiSgmnts - Cell array of selected chi structures 
	%		and if 'down' is selected:
	%		Heads - nx3 matrix of channel heads you picked with pick number, x cooord, and y coordinate as the columns
	%		and if 'up' is selected:
	%		Outlets - nx3 matrix of outlets you picked with pick number, x cooord, and y coordinate as the columns
	%
	% Examples:
	%	SegmentPicker(DEM,FD,A,S,2);
	%	SegmentPicker(DEM,FD,A,S,2,'direction','up','theta_ref',0.6,'min_grad',0.00001);
	%	SegmentPicker(DEM,FD,A,S,32,'direction','down','theta_ref',0.5,'min_elev',300,'recalc',true);
	%	SegmentPicker(DEM,FD,A,S,1,'method','prev_picks','picks',channel_heads); % If inputing a matrix named channel_heads
	%	SegmentPicker(DEM,FD,A,S,1,'method','prev_picks','picks','channel_heads'); % If inputing a shapefile named channel_heads.shp
	%
	%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
	% Function Written by Adam M. Forte - Last Revised Winter 2017 %
	%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

	% Parse Inputs
	p = inputParser;
	p.FunctionName = 'SegmentPicker';
	addRequired(p,'DEM',@(x) isa(x,'GRIDobj'));
	addRequired(p,'FD',@(x) isa(x,'FLOWobj'));
	addRequired(p,'A',@(x) isa(x,'GRIDobj'));
	addRequired(p,'S',@(x) isa(x,'STREAMobj'));
	addRequired(p,'basin_num',@(x) isnumeric(x));

	addParamValue(p,'direction','down',@(x) ischar(validatestring(x,{'down','up'})));
	addParamValue(p,'method','new_picks',@(x) ischar(validatestring(x,{'new_picks','prev_picks'})));
	addParamValue(p,'plot_type','vector',@(x) ischar(validatestring(x,{'vector','grid'})));	
	addParamValue(p,'plot_style','refresh',@(x) ischar(validatestring(x,{'refresh','keep'})));
	addParamValue(p,'complete_networks_only',false,@(x) isscalar(x) && islogical(x));
	addParamValue(p,'ref_concavity',0.50,@(x) isscalar(x) && isnumeric(x));
	addParamValue(p,'min_elev',[],@(x) isscalar(x) && isnumeric(x));
	addParamValue(p,'max_area',[],@(x) isscalar(x) && isnumeric(x));
	addParamValue(p,'recalc',false,@(x) isscalar(x));
	addParamValue(p,'picks',[],@(x) (isnumeric(x) && size(x,2)==3) | ischar(x));
	addParamValue(p,'threshold_area',1e6,@(x) isnumeric(x));
	addParamValue(p,'conditioned_DEM',[],@(x) isa(x,'GRIDobj'));
	addParamValue(p,'interp_value',0.1,@(x) isnumeric(x) && x>=0 && x<=1);

	parse(p,DEM,FD,A,S,basin_num,varargin{:});
	DEM=p.Results.DEM;
	FD=p.Results.FD;
	S=p.Results.S;
	A=p.Results.A;
	basin_num=p.Results.basin_num;

	cno=p.Results.complete_networks_only;
	direction=p.Results.direction;
	method=p.Results.method;
	theta_ref=p.Results.ref_concavity;
	plot_type=p.Results.plot_type;
	plot_style=p.Results.plot_style;
	threshold_area=p.Results.threshold_area;
	points=p.Results.picks;
	iv=p.Results.interp_value;
	DEMc=p.Results.conditioned_DEM;


	% Catch errors
	if strcmp(direction,'up') && ~isempty(p.Results.min_elev)
		warning('Input for minimum elevation is ignored when picking streams up from a pour point')
	elseif strcmp(direction,'up') && ~isempty(p.Results.max_area)
		warning('Input for maximum drainage area is ignored when picking streams up from a pour point')
	elseif ~isempty(p.Results.min_elev) && ~isempty(p.Results.max_area)
		error('Cannot specify both a minimum elevation and a maximum area, please provide one input only')
	elseif strcmp(method,'prev_picks') && isempty(p.Results.picks)
		error('If you choose the previous picks method you must provide a list of outlets or channel heads') 
	end

	% Parse different inputs
	if strcmp(direction,'down') & strcmp(plot_style,'keep');
		plot_switch='down_keep';
	elseif strcmp(direction,'down') & strcmp(plot_style,'refresh');
		plot_switch='down_ref';
	elseif strcmp(direction,'up') & strcmp(plot_style,'keep');
		plot_switch='up_keep';
	elseif strcmp(direction,'up') & strcmp(plot_style,'refresh');
		plot_switch='up_ref';
	end

    if strcmp(method,'prev_picks') & isempty(points)
        error('Please provide a m x 3 array of points or the valid path to a shapefile of points');
    elseif strcmp(method,'prev_picks') & ischar(points)
        disp('Reading shapefile')
        try
            pt_name=[points '.shp'];
            pt_shp=shaperead(pt_name);
            fn=fieldnames(pt_shp);
            pt=horzcat([pt_shp.(fn{4})]',[pt_shp.X]',[pt_shp.Y]');
        catch
            error('Error reading shapefile, make sure the name provided did NOT include .shp, the shapefile is a point file with a single value column, and you have a license for the Mapping Toolbox');
        end
    end

    % Remove edges if flag is thrown
    if cno
    	S=removeedgeeffects(S,FD,DEM);
    end


	% Hydrologically condition dem
	if isempty(DEMc)
		zc=mincosthydrocon(S,DEM,'interp',iv);
		DEMc=GRIDobj(DEM);
		DEMc.Z(DEMc.Z==0)=NaN;
		DEMc.Z(S.IXgrid)=zc;
	end

	switch plot_type
	case 'grid'
		DA=A.*(A.cellsize^2);
		DA.Z(DA.Z<threshold_area)=0;
		LA=log10(DA);
	end

	colcol=colorcube(10);
	
	switch method
	case 'new_picks'
		switch plot_switch
		% Extract points downstream from a channel head selection
		case 'down_keep'

			str1='N';
			str2='Y';

			ii=1;
			close all
			f1=figure(1);
			set(f1,'Units','normalized','Position',[0.05 0.1 0.45 0.8],'renderer','painters');
			clf
			switch plot_type
			case 'grid'
				hold on
				imageschs(DEM,LA,'colormap','parula','colorbar',false);
				hold off
			case 'vector'
				hold on
				imageschs(DEM,DEM,'colormap','parula','colorbar',false);
				plot(S,'-w');
				hold off
			end

			while strcmpi(str2,'Y')         
				while strcmpi(str1,'N')    	
					
					% Reset short circuit switch
					short_circ=0;

					figure(f1)
					hold on
					title('Zoom and pan to area of interest and press "return/enter" when ready to pick')
					hold off
					pause()

					hold on
					title('Choose point near channel head of interest')
					hold off
					[x,y]=ginput(1);
					pOI=[x y];

					% Find nearest channel head
					[ch]=streampoi(S,'channelheads','xy');
					distance=sqrt(sum(bsxfun(@minus, ch, pOI).^2,2));
					chOI=ch(distance==min(distance),:);

					% Build logical raster
					ix=coord2ind(DEM,chOI(:,1),chOI(:,2));
					IX=GRIDobj(DEM);
					IX.Z(ix)=1;
					[ixmat,X,Y]=GRIDobj2mat(IX);
					ixmat=logical(ixmat);
					IX=GRIDobj(X,Y,ixmat);

					% Extract stream from channel head to outlet
					Sn_t=modify(S,'downstreamto',IX);

					% Check if additional constraints have been specified
					if ~isempty(p.Results.max_area)
						AR=A.*(A.cellsize^2);
						ar=getnal(Sn_t,AR);

						sx=Sn_t.x; sy=Sn_t.y;
						d=Sn_t.distance;
						[d_s,d_ix]=sort(d,'ascend');
						ar_s=ar(d_ix);
						sx=sx(d_ix); sy=sy(d_ix);

						ma=p.Results.max_area;

						ix2=find(ar_s>=ma,1,'last');
						if isempty(ix2)
							warning('Input maximum drainage area is too large, extracting full stream')
							Sn=Sn_t;
							short_circ=1;
						elseif ix2==numel(ar)
							error('Input maximum drainage area is too small, no portion of the stream selected')
						else
							xn=sx(ix2);
							yn=sy(ix2);

							ix2=coord2ind(DEM,xn,yn);
							IX2=GRIDobj(DEM);
							IX2.Z(ix2)=1;
							[ix2mat,X,Y]=GRIDobj2mat(IX2);
							ix2mat=logical(ix2mat);
							IX2=GRIDobj(X,Y,ix2mat);

							Sn=modify(Sn_t,'upstreamto',IX2);
						end

					elseif ~isempty(p.Results.min_elev);
						el=getnal(Sn_t,DEMc);

						sx=Sn_t.x; sy=Sn_t.y;
						d=Sn_t.distance;
						[d_s,d_ix]=sort(d,'ascend');
						el_s=el(d_ix);
						sx=sx(d_ix); sy=sy(d_ix);

						me=p.Results.min_elev;

						ix2=find(el_s>=me,1,'first');
						if ix2==1
							warning('Input minimum elevation is too low, extracting full stream')
							Sn=Sn_t;
							short_circ=1;
						elseif isempty(ix2)
							error('Input minimum elevation is too high, no portion of the stream selected')
						else
							xn=sx(ix2);
							yn=sy(ix2);

							ix2=coord2ind(DEM,xn,yn);
							IX2=GRIDobj(DEM);
							IX2.Z(ix2)=1;
							[ix2mat,X,Y]=GRIDobj2mat(IX2);
							ix2mat=logical(ix2mat);
							IX2=GRIDobj(X,Y,ix2mat);

							Sn=modify(Sn_t,'upstreamto',IX2);
						end
					else
						Sn=Sn_t;
					end

					hold on
					plot(Sn,'-r','LineWidth',2);
					hold off

		            qa=questdlg('Is this the stream segment you wanted?','Stream Selection','No','Yes','Yes');

		            switch qa
		            case 'Yes'
		                str1 = 'Y';
		            case 'No'
		                str1 = 'N';
		            end
				end

				if isempty(p.Results.min_elev) && isempty(p.Results.max_area) 
					C=chiplot(Sn,DEMc,A,'a0',1,'mn',theta_ref,'plot',false);
				elseif ~isempty(p.Results.min_elev) | ~isempty(p.Results.max_area) && p.Results.recalc
					C=chiplot(Sn,DEMc,A,'a0',1,'mn',theta_ref,'plot',false);
				elseif short_circ==1;
					C=chiplot(Sn,DEMc,A,'a0',1,'mn',theta_ref,'plot',false);
				elseif ~isempty(p.Results.min_elev) | ~isempty(p.Results.max_area) && p.Results.recalc==0
					C_t=chiplot(Sn_t,DEMc,A,'a0',1,'mn',theta_ref,'plot',false);
					C_n=chiplot(Sn,DEMc,A,'a0',1,'mn',theta_ref,'plot',false);

					% Find extents
					txyz=[C_t.x C_t.y C_t.elev];
					nxyz=[C_n.x C_n.y C_n.elev];
					ix3=ismember(txyz,nxyz,'rows');
					% Remake chi structure
					C=struct;
					C.mn=C_n.mn;
					C.beta=C_n.beta;
					C.betase=C_n.betase;
					C.a0=C_n.a0;
					C.ks=C_n.ks;
					C.R2=C_n.R2;
					C.chi=C_t.chi(ix3);
					C.x=C_t.x(ix3); C.y=C_t.y(ix3);
					C.elev=C_t.elev(ix3); C.elevbl=C_t.elevbl(ix3);
					C.distance=C_t.distance(ix3); C.pred=C_t.pred(ix3);
					C.area=C_t.area(ix3); C.res=C_t.res(ix3);
				end

				f2=figure(2);
				set(f2,'Units','normalized','Position',[0.5 0.1 0.45 0.8],'renderer','painters');

				subplot(3,1,1);
				hold on
				plot(C.chi,C.elev,'Color',colcol(mod(ii,10)+1,:));
				xlabel('\chi')
				ylabel('Elevation (m)')
				title('\chi - Z')
				hold off

				subplot(3,1,2);
				hold on
				if isempty(p.Results.min_elev) && isempty(p.Results.max_area) 
					plotdz(Sn,DEM,'dunit','km','Color',[0.5 0.5 0.5]);
					plotdz(Sn,DEMc,'dunit','km','Color',colcol(mod(ii,10)+1,:));
				elseif ~isempty(p.Results.min_elev) | ~isempty(p.Results.max_area) && p.Results.recalc
					plotdz(Sn,DEM,'dunit','km','Color',[0.5 0.5 0.5]);
					plotdz(Sn,DEMc,'dunit','km','Color',colcol(mod(ii,10)+1,:));
				elseif short_circ==1;
					plotdz(Sn,DEM,'dunit','km','Color',[0.5 0.5 0.5]);
					plotdz(Sn,DEMc,'dunit','km','Color',colcol(mod(ii,10)+1,:));
				elseif ~isempty(p.Results.min_elev) | ~isempty(p.Results.max_area) && p.Results.recalc==0
					Cu=chiplot(Sn_t,DEM,A,'a0',1,'mn',theta_ref,'plot',false);
					plot((Cu.distance(ix3))./1000,Cu.elev(ix3),'Color',[0.5 0.5 0.5]);
					% plot(C.distance./1000,C.elev,'-k');
					plot(C.distance./1000,C.elev,'Color',colcol(mod(ii,10)+1,:));
				end
				xlabel('Distance from Mouth (km)')
				ylabel('Elevation (m)')
				% legend('Unconditioned DEM','Conditioned DEM','location','best');
				title('Long Profile')
				hold off

				saax=subplot(3,1,3);
				hold on
				if isempty(p.Results.min_elev) && isempty(p.Results.max_area) 
					[bs,ba]=sa(DEMc,Sn,A);
				elseif ~isempty(p.Results.min_elev) | ~isempty(p.Results.max_area) && p.Results.recalc								
					[bs,ba]=sa(DEMc,Sn,A);
				elseif short_circ==1;
					[bs,ba]=sa(DEMc,Sn,A);
				elseif ~isempty(p.Results.min_elev) | ~isempty(p.Results.max_area) && p.Results.recalc==0
					[bs,ba]=sa(DEMc,Sn_t,A);
				end
				scatter(ba,bs,10,colcol(mod(ii,10)+1,:));
				set(saax,'Xscale','log','Yscale','log','XDir','reverse');
				xlabel('Log Drainage Area');
				ylabel('Log Slope');	
				hold off

				StreamSgmnts{ii}=Sn;
				ChiSgmnts{ii}=C;
				Heads(ii,1)=ii;
				Heads(ii,2)=chOI(:,1);
				Heads(ii,3)=chOI(:,2);

				ii=ii+1;

	            qa2=questdlg('Pick a different stream?','Stream Selection','No','Yes','Yes');
	            switch qa2
	            case 'Yes'
	            	str2 = 'Y';
	                str1 = 'N';
	            case 'No'
	                str2 = 'N';
	            end				
			end

			fileOut=['PickedSegments_' num2str(basin_num) '.mat'];
			save(fileOut,'StreamSgmnts','ChiSgmnts','Heads');

		% Extract segements upstream from a pour point selection
		case 'up_keep'

			str1='N';
			str2='Y';

			ii=1;
	
			f1=figure(1);
			set(f1,'Units','normalized','Position',[0.05 0.1 0.45 0.8],'renderer','painters');
			clf
			switch plot_type
			case 'grid'
				hold on
				imageschs(DEM,LA,'colormap','parula','colorbar',false);
				hold off
			case 'vector'
				hold on
				imageschs(DEM,DEM,'colormap','parula','colorbar',false);
				plot(S,'-w');
				hold off
			end

			while strcmpi(str2,'Y')       
				while strcmpi(str1,'N')   	

					figure(f1)
					hold on
					title('Zoom and pan to area of interest and press "return/enter" when ready to pick')
					hold off
					pause()

					hold on
					title('Choose point above to which calculate Chi-Z')
					hold off

					[x,y]=ginput(1);

					% Build logical raster
					[xn,yn]=snap2stream(S,x,y);
					ix=coord2ind(DEM,xn,yn);
					IX=GRIDobj(DEM);
					IX.Z(ix)=1;
					[ixmat,X,Y]=GRIDobj2mat(IX);
					ixmat=logical(ixmat);
					IX=GRIDobj(X,Y,ixmat);

					Sn=modify(S,'upstreamto',IX);

					hold on
					plot(Sn,'-r','LineWidth',2);
					hold off

		            qa=questdlg('Is this the stream segment you wanted?','Stream Selection','No','Yes','Yes');
		            switch qa
		            case 'Yes'
		                str1 = 'Y';
		            case 'No'
		                str1 = 'N';
		            end
				end

				C=chiplot(Sn,DEMc,A,'a0',1,'mn',theta_ref,'plot',false);

				f2=figure(2);
				set(f2,'Units','normalized','Position',[0.5 0.1 0.45 0.8],'renderer','painters');

				subplot(3,1,1);
				hold on
				plot(C.chi,C.elev);
				xlabel('\chi')
				ylabel('Elevation (m)')
				title('\chi - Z')
				hold off

				subplot(3,1,2);
				hold on
				plotdz(Sn,DEMc,'dunit','km');
				xlabel('Distance from Mouth (km)')
				ylabel('Elevation (m)')
				title('Long Profile')
				hold off

				saax=subplot(3,1,3);
				hold on
				[bs,ba]=sa(DEMc,Sn,A);
				scatter(ba,bs,'filled');
				set(saax,'Xscale','log','Yscale','log','XDir','reverse');
				xlabel('Log Drainage Area');
				ylabel('Log Slope');	
				hold off

				StreamSgmnts{ii}=Sn;
				ChiSgmnts{ii}=C;
				Outlets(ii,1)=ii;
				Outlets(ii,2)=xn;
				Outlets(ii,3)=yn;

				ii=ii+1;


	            qa2=questdlg('Pick a different stream?','Stream Selection','No','Yes','Yes');
	            switch qa2
	            case 'Yes'
	            	str2 = 'Y';
	                str1 = 'N';
	            case 'No'
	                str2 = 'N';
	            end
			end

			fileOut=['PickedSegments_' num2str(basin_num) '.mat'];
			save(fileOut,'StreamSgmnts','ChiSgmnts','Outlets');

		case 'down_ref'

			str1='N';
			str2='Y';

			ii=1;

			f1=figure(1);
			set(f1,'Units','normalized','Position',[0.05 0.1 0.45 0.8],'renderer','painters');
			clf
			switch plot_type
			case 'grid'
				hold on
				imageschs(DEM,LA,'colormap','parula','colorbar',false);
				hold off
			case 'vector'
				hold on
				imageschs(DEM,DEM,'colormap','parula','colorbar',false);
				plot(S,'-w');
				hold off
			end

			while strcmpi(str2,'Y')     
				while strcmpi(str1,'N')    	
					
					% Reset short circuit switch
					short_circ=0;

					figure(1)
					hold on
					title('Zoom and pan to area of interest and press "return/enter" when ready to pick')
					hold off
					pause()

					hold on
					title('Choose point near channel head of interest')
					hold off
					[x,y]=ginput(1);
					pOI=[x y];

					% Find nearest channel head
					[ch]=streampoi(S,'channelheads','xy');
					distance=sqrt(sum(bsxfun(@minus, ch, pOI).^2,2));
					chOI=ch(distance==min(distance),:);

					% Build logical raster
					ix=coord2ind(DEM,chOI(:,1),chOI(:,2));
					IX=GRIDobj(DEM);
					IX.Z(ix)=1;
					[ixmat,X,Y]=GRIDobj2mat(IX);
					ixmat=logical(ixmat);
					IX=GRIDobj(X,Y,ixmat);

					% Extract stream from channel head to outlet
					Sn_t=modify(S,'downstreamto',IX);

					% Check if additional constraints have been specified
					if ~isempty(p.Results.max_area)
						AR=A.*(A.cellsize^2);
						ar=getnal(Sn_t,AR);

						sx=Sn_t.x; sy=Sn_t.y;
						d=Sn_t.distance;
						[d_s,d_ix]=sort(d,'ascend');
						ar_s=ar(d_ix);
						sx=sx(d_ix); sy=sy(d_ix);

						ma=p.Results.max_area;

						ix2=find(ar_s>=ma,1,'last');
						if isempty(ix2)
							warning('Input maximum drainage area is too large, extracting full stream')
							Sn=Sn_t;
							short_circ=1;
						elseif ix2==numel(ar)
							error('Input maximum drainage area is too small, no portion of the stream selected')
						else
							xn=sx(ix2);
							yn=sy(ix2);

							ix2=coord2ind(DEM,xn,yn);
							IX2=GRIDobj(DEM);
							IX2.Z(ix2)=1;
							[ix2mat,X,Y]=GRIDobj2mat(IX2);
							ix2mat=logical(ix2mat);
							IX2=GRIDobj(X,Y,ix2mat);

							Sn=modify(Sn_t,'upstreamto',IX2);
						end

					elseif ~isempty(p.Results.min_elev);
						el=getnal(Sn_t,DEMc);

						sx=Sn_t.x; sy=Sn_t.y;
						d=Sn_t.distance;
						[d_s,d_ix]=sort(d,'ascend');
						el_s=el(d_ix);
						sx=sx(d_ix); sy=sy(d_ix);

						me=p.Results.min_elev;

						ix2=find(el_s>=me,1,'first');
						if ix2==1
							warning('Input minimum elevation is too low, extracting full stream')
							Sn=Sn_t;
							short_circ=1;
						elseif isempty(ix2)
							error('Input minimum elevation is too high, no portion of the stream selected')
						else
							xn=sx(ix2);
							yn=sy(ix2);

							ix2=coord2ind(DEM,xn,yn);
							IX2=GRIDobj(DEM);
							IX2.Z(ix2)=1;
							[ix2mat,X,Y]=GRIDobj2mat(IX2);
							ix2mat=logical(ix2mat);
							IX2=GRIDobj(X,Y,ix2mat);

							Sn=modify(Sn_t,'upstreamto',IX2);
						end
					else
						Sn=Sn_t;
					end

					hold on
					plot(Sn,'-r','LineWidth',2);
					hold off


		            qa=questdlg('Is this the stream segment you wanted?','Stream Selection','No','Yes','Yes');
		            switch qa
		            case 'Yes'
		                str1 = 'Y';
		            case 'No'
		                str1 = 'N';
		            end

				end

				if isempty(p.Results.min_elev) && isempty(p.Results.max_area) 
					C=chiplot(Sn,DEMc,A,'a0',1,'mn',theta_ref,'plot',false);
				elseif ~isempty(p.Results.min_elev) | ~isempty(p.Results.max_area) && p.Results.recalc
					C=chiplot(Sn,DEMc,A,'a0',1,'mn',theta_ref,'plot',false);
				elseif short_circ==1;
					C=chiplot(Sn,DEMc,A,'a0',1,'mn',theta_ref,'plot',false);
				elseif ~isempty(p.Results.min_elev) | ~isempty(p.Results.max_area) && p.Results.recalc==0
					C_t=chiplot(Sn_t,DEMc,A,'a0',1,'mn',theta_ref,'plot',false);
					C_n=chiplot(Sn,DEMc,A,'a0',1,'mn',theta_ref,'plot',false);

					% Find extents
					txyz=[C_t.x C_t.y C_t.elev];
					nxyz=[C_n.x C_n.y C_n.elev];
					ix3=ismember(txyz,nxyz,'rows');
					% Remake chi structure
					C=struct;
					C.mn=C_n.mn;
					C.beta=C_n.beta;
					C.betase=C_n.betase;
					C.a0=C_n.a0;
					C.ks=C_n.ks;
					C.R2=C_n.R2;
					C.chi=C_t.chi(ix3);
					C.x=C_t.x(ix3); C.y=C_t.y(ix3);
					C.elev=C_t.elev(ix3); C.elevbl=C_t.elevbl(ix3);
					C.distance=C_t.distance(ix3); C.pred=C_t.pred(ix3);
					C.area=C_t.area(ix3); C.res=C_t.res(ix3);
				end

				f2=figure(2);
				set(f2,'Units','normalized','Position',[0.5 0.1 0.45 0.8],'renderer','painters');

				subplot(3,1,1);
				hold on
				plot(C.chi,C.elev,'-k');
				xlabel('\chi')
				ylabel('Elevation (m)')
				title('\chi - Z')
				hold off

				subplot(3,1,2);
				hold on
				if isempty(p.Results.min_elev) && isempty(p.Results.max_area) 
					plotdz(Sn,DEM,'dunit','km','Color',[0.5 0.5 0.5]);
					plotdz(Sn,DEMc,'dunit','km','Color','k');
				elseif ~isempty(p.Results.min_elev) | ~isempty(p.Results.max_area) && p.Results.recalc
					plotdz(Sn,DEM,'dunit','km','Color',[0.5 0.5 0.5]);
					plotdz(Sn,DEMc,'dunit','km','Color','k');
				elseif short_circ==1;
					plotdz(Sn,DEM,'dunit','km','Color',[0.5 0.5 0.5]);
					plotdz(Sn,DEMc,'dunit','km','Color','k');
				elseif ~isempty(p.Results.min_elev) | ~isempty(p.Results.max_area) && p.Results.recalc==0
					Cu=chiplot(Sn_t,DEM,A,'a0',1,'mn',theta_ref,'plot',false);
					plot((Cu.distance(ix3))./1000,Cu.elev(ix3),'Color',[0.5 0.5 0.5]);
					plot(C.distance./1000,C.elev,'-k');
				end
				xlabel('Distance from Mouth (km)')
				ylabel('Elevation (m)')
				legend('Unconditioned DEM','Conditioned DEM','location','best');
				title('Long Profile')
				hold off


				saax=subplot(3,1,3);
				hold on
				if isempty(p.Results.min_elev) && isempty(p.Results.max_area) 
					[bs,ba]=sa(DEMc,Sn,A);
				elseif ~isempty(p.Results.min_elev) | ~isempty(p.Results.max_area) && p.Results.recalc								
					[bs,ba]=sa(DEMc,Sn,A);
				elseif short_circ==1;
					[bs,ba]=sa(DEMc,Sn,A);
				elseif ~isempty(p.Results.min_elev) | ~isempty(p.Results.max_area) && p.Results.recalc==0
					[bs,ba]=sa(DEMc,Sn_t,A);
				end
				scatter(ba,bs,10,'k','filled');
				set(saax,'Xscale','log','Yscale','log','XDir','reverse');
				xlabel('Log Drainage Area');
				ylabel('Log Slope');	
				hold off								

				StreamSgmnts{ii}=Sn;
				ChiSgmnts{ii}=C;
				Heads(ii,1)=ii;
				Heads(ii,2)=chOI(:,1);
				Heads(ii,3)=chOI(:,2);

				ii=ii+1;

	            qa2=questdlg('Pick a different stream?','Stream Selection','No','Yes','Yes');
	            switch qa2
	            case 'Yes'
	            	str2 = 'Y';
	                str1 = 'N';
	                close figure 2
	            case 'No'
	                str2 = 'N';
	            end	

			end

			fileOut=['PickedSegments_' num2str(basin_num) '.mat'];
			save(fileOut,'StreamSgmnts','ChiSgmnts','Heads');

		% Extract segements upstream from a pour point selection
		case 'up_ref'

			str1='N';
			str2='Y';

			ii=1;
			f1=figure(1);
			set(f1,'Units','normalized','Position',[0.05 0.1 0.45 0.8],'renderer','painters');
			clf
			switch plot_type
			case 'grid'
				hold on
				imageschs(DEM,LA,'colormap','parula','colorbar',false);
				hold off
			case 'vector'
				hold on
				imageschs(DEM,DEM,'colormap','parula','colorbar',false);
				plot(S,'-w');
				hold off
			end

			while strcmpi(str2,'Y')        
				while strcmpi(str1,'N')   	
					
					figure(1);
					hold on
					title('Zoom and pan to area of interest and press "return/enter" when ready to pick')
					hold off
					pause()

					hold on
					title('Choose point above to which calculate Chi-Z')
					hold off
					[x,y]=ginput(1);

					% Build logical raster
					[xn,yn]=snap2stream(S,x,y);
					ix=coord2ind(DEM,xn,yn);
					IX=GRIDobj(DEM);
					IX.Z(ix)=1;
					[ixmat,X,Y]=GRIDobj2mat(IX);
					ixmat=logical(ixmat);
					IX=GRIDobj(X,Y,ixmat);

					Sn=modify(S,'upstreamto',IX);

					hold on
					plot(Sn,'-r','LineWidth',2);
					hold off

		            qa=questdlg('Is this the stream segment you wanted?','Stream Selection','No','Yes','Yes');
		            switch qa
		            case 'Yes'
		                str1 = 'Y';
		            case 'No'
		                str1 = 'N';
		            end
				end

				C=chiplot(Sn,DEMc,A,'a0',1,'mn',theta_ref,'plot',false);

				f2=figure(2);
				set(f2,'Units','normalized','Position',[0.5 0.1 0.45 0.8],'renderer','painters');
				subplot(3,1,1);
				hold on
				plot(C.chi,C.elev,'-k');
				xlabel('\chi')
				ylabel('Elevation (m)')
				title('\chi - Z')
				hold off

				subplot(3,1,2);
				hold on
				plotdz(Sn,DEMc,'dunit','km','Color','k');
				xlabel('Distance from Mouth (km)')
				ylabel('Elevation (m)')
				title('Long Profile')
				hold off

				saax=subplot(3,1,3);
				hold on
				[bs,ba]=sa(DEMc,Sn,A);
				scatter(ba,bs,10,'k','filled');
				set(saax,'Xscale','log','Yscale','log','XDir','reverse');
				xlabel('Log Drainage Area');
				ylabel('Log Slope');	
				hold off

				StreamSgmnts{ii}=Sn;
				ChiSgmnts{ii}=C;
				Outlets(ii,1)=ii;
				Outlets(ii,2)=xn;
				Outlets(ii,3)=yn;

				ii=ii+1;

	            qa2=questdlg('Pick a different stream?','Stream Selection','No','Yes','Yes');
	            switch qa2
	            case 'Yes'
	            	str2 = 'Y';
	                str1 = 'N';
	                close figure 2
	            case 'No'
	                str2 = 'N';
	            end	

			end

			fileOut=['PickedSegments_' num2str(basin_num) '.mat'];
			save(fileOut,'StreamSgmnts','ChiSgmnts','Outlets');
		end
		
	% Previous Picks
	case 'prev_picks'
		switch direction
		case 'down'
			heads=pt;
			[num_heads,~]=size(heads);

			w1=waitbar(0,'Extracting segments');
			for ii=1:num_heads
				short_circ=0;
				x=heads(ii,2); y=heads(ii,3);
				pOI=[x y];

				% Find nearest channel head
				[ch]=streampoi(S,'channelheads','xy');
				distance=sqrt(sum(bsxfun(@minus, ch, pOI).^2,2));
				chOI=ch(distance==min(distance),:);

				% Build logical raster
				ix=coord2ind(DEM,chOI(:,1),chOI(:,2));
				IX=GRIDobj(DEM);
				IX.Z(ix)=1;
				[ixmat,X,Y]=GRIDobj2mat(IX);
				ixmat=logical(ixmat);
				IX=GRIDobj(X,Y,ixmat);

				% Extract stream from channel head to outlet
				Sn_t=modify(S,'downstreamto',IX);

				% Check if additional constraints have been specified
				if ~isempty(p.Results.max_area)
					AR=A.*(A.cellsize^2);

					sx=Sn_t.x; sy=Sn_t.y;
					d=Sn_t.distance;
					[d_s,d_ix]=sort(d,'ascend');
					ar_s=ar(d_ix);
					sx=sx(d_ix); sy=sy(d_ix);

					ix2=find(ar_s>=ma,1,'last');
					if isempty(ix2)
						warning('Input maximum drainage area is too large, extracting full stream')
						Sn=Sn_t;
						short_circ=1;
					elseif ix2==numel(ar)
						error('Input maximum drainage area is too small, no portion of the stream selected')
					else
						xn=sx(ix2);
						yn=sy(ix2);

						ix2=coord2ind(DEM,xn,yn);
						IX2=GRIDobj(DEM);
						IX2.Z(ix2)=1;
						[ix2mat,X,Y]=GRIDobj2mat(IX2);
						ix2mat=logical(ix2mat);
						IX2=GRIDobj(X,Y,ix2mat);

						Sn=modify(Sn_t,'upstreamto',IX2);
					end

				elseif ~isempty(p.Results.min_elev);
					el=getnal(Sn_t,DEMc);

					sx=Sn_t.x; sy=Sn_t.y;
					d=Sn_t.distance;
					[d_s,d_ix]=sort(d,'ascend');
					el_s=el(d_ix);
					sx=sx(d_ix); sy=sy(d_ix);

					me=p.Results.min_elev;

					ix2=find(el_s>=me,1,'first');
					if ix2==1
						warning('Input minimum elevation is too low, extracting full stream')
						Sn=Sn_t;
					elseif isempty(ix2)
						error('Input minimum elevation is too high, no portion of the stream selected')
					else
						xn=sx(ix2);
						yn=sy(ix2);

						ix2=coord2ind(DEM,xn,yn);
						IX2=GRIDobj(DEM);
						IX2.Z(ix2)=1;
						[ix2mat,X,Y]=GRIDobj2mat(IX2);
						ix2mat=logical(ix2mat);
						IX2=GRIDobj(X,Y,ix2mat);

						Sn=modify(Sn_t,'upstreamto',IX2);
					end
				else
					Sn=Sn_t;
				end

				if isempty(p.Results.min_elev) && isempty(p.Results.max_area) 
					C=chiplot(Sn,DEMc,A,'a0',1,'mn',theta_ref,'plot',false);
				elseif ~isempty(p.Results.min_elev) | ~isempty(p.Results.max_area) && p.Results.recalc
					C=chiplot(Sn,DEMc,A,'a0',1,'mn',theta_ref,'plot',false);
				elseif short_circ==1;
					C=chiplot(Sn,DEMc,A,'a0',1,'mn',theta_ref,'plot',false);
				elseif ~isempty(p.Results.min_elev) | ~isempty(p.Results.max_area) && p.Results.recalc==0
					C_t=chiplot(Sn_t,DEMc,A,'a0',1,'mn',theta_ref,'plot',false);
					C_n=chiplot(Sn,DEMc,A,'a0',1,'mn',theta_ref,'plot',false);

					% Find extents
					txyz=[C_t.x C_t.y C_t.elev];
					nxyz=[C_n.x C_n.y C_n.elev];
					ix3=ismember(txyz,nxyz,'rows');

					% Remake chi structure
					C=C_t;
					C.chi=C_t.chi(ix3);
					C.x=C_t.x(ix3); C.y=C_t.y(ix3);
					C.elev=C_t.elev(ix3); C.elevbl=C_t.elevbl(ix3);
					C.distance=C_t.distance(ix3); C.pred=C_t.pred(ix3);
					C.area=C_t.area(ix3); C.res=C_t.res(ix3);
				end

				StreamSgmnts{ii}=Sn;
				ChiSgmnts{ii}=C;
				Heads(ii,1)=ii;
				Heads(ii,2)=chOI(:,1);
				Heads(ii,3)=chOI(:,2);
				waitbar(ii/num_heads);
			end
			close(w1);

			fileOut=['PickedSegments_' num2str(basin_num) '.mat'];
			save(fileOut,'StreamSgmnts','ChiSgmnts','Heads');

		case 'up'
			outlets=pt;
			[num_outs,~]=size(outlets);

			w1=waitbar(0,'Extracting segments');
			for ii=1:num_outs
				x=outlets(ii,2); y=outlets(ii,3);
				% Build logical raster
				[xn,yn]=snap2stream(S,x,y);
				ix=coord2ind(DEM,xn,yn);
				IX=GRIDobj(DEM);
				IX.Z(ix)=1;
				[ixmat,X,Y]=GRIDobj2mat(IX);
				ixmat=logical(ixmat);
				IX=GRIDobj(X,Y,ixmat);


				Sn=modify(S,'upstreamto',IX);
				Sn=klargestconncomps(Sn,1);
				C=chiplot(Sn,DEMc,A,'a0',1,'mn',theta_ref,'plot',false);

				StreamSgmnts{ii}=Sn;
				ChiSgmnts{ii}=C;
				Outlets(ii,1)=ii;
				Outlets(ii,2)=xn;
				Outlets(ii,3)=yn;
				waitbar(ii/num_outs);
			end
			close(w1);

			fileOut=['PickedSegments_' num2str(basin_num) '.mat'];
			save(fileOut,'StreamSgmnts','ChiSgmnts','Outlets');
		end
	end
% Main Function End
end

function [bs,ba]=sa(DEM,S,A)
	% Stripped down and tweaked version of 'slopearea' function

	numbins=100;

	a=getnal(S,A.*A.cellsize^2);
	z=getnal(S,DEM);
	g=gradient(S,z,'unit','tangent'); % Already a conditioned DEM

	mina=min(a);
	maxa=max(a);

    edges = logspace(log10(mina-0.1),log10(maxa+1),numbins+1);
    try
    	% histc is deprecated
    	[ix]=discretize(a,edges);
    catch
	    [~,ix] = histc(a,edges);
	end

	ba=accumarray(ix,a,[numbins 1],@median,nan);
	bs=accumarray(ix,g,[numbins 1],@(x) mean(x(~isnan(x))),nan);
end





