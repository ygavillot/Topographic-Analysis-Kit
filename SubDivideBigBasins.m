function SubDivideBigBasins(basin_dir,max_basin_size,divide_method,varargin)
	%
	% Usage:
	%	SubDivideBigBasins(basin_dir,max_basin_size,divide_method);
	%	SubDivideBigBasins(basin_dir,max_basin_size,divide_method,'name',value,...);
	%
	% Description:
	% 	Function takes outputs from 'ProcessRiverBasins' function and subdvides any basin with a drainage area above a specified size and
	% 	outputs clipped dem, stream network, variout topographic metrics, and river values (ks, ksn, chi)
	%
	% Required Inputs:
	% 		basin_dir - full path of folder which contains the mat files from 'ProcessRiverBasins'
	% 		max_basin_size - size above which drainage basins will be subdivided in square kilometers
	%		divide_method - method for subdividing basins, options are ('confluences' and 'up_confluences' is NOT recommended large datasets):
	%			'order' - use the outlets of streams of a given order that the user can specify with the optional 's_order' parameter 
	%			'confluences' - use the locations of confluences (WILL PRODUCE A LOT OF SUB BASINS!). There is an internal parameter to remove
	%				extremely short streams that would otherwise result in the code erroring out.
	%			'up_confluences' - use locations just upstream of confluences (WILL PRODUCE A LOT OF SUB BASINS!). There is an internal parameter
	%				to remove extremely short streams that otherwise result in the code erroring out.
	%			'filtered_confluences' - use locations of confluences if drainage basin above confluence is of a specified size that the user
	%				can specify with the optional 'min_basin_size'  
	%			'p_filtered_confluences' - similar to filtered confluences, but the user defines a percentage of the main basin area
	%				with the optional 'min_basin_size'
	%			'trunk' - uses the tributary junctions with the trunk stream within the main basin as pour points for subdivided basins. There is
	%				an internal parameter to remove extremely short streams that would otherwise result in the code erroring out.
	%			'filtered_trunk' - same as 'trunk' but will only include basins that are greater than the min_basin_size
	%			'p_filtered_trunk' - same as 'filtered_trunk' but 'min_basin_size' is interpreted as a percentage of the main basin area
	%
	% Optional Inputs:
	%		SBFiles_Dir ['SubBasins'] - name of folder (within the main Basins folder) to store the subbasin files. Subbasin files are now stored in
	%			a separate folder to aid in the creation of different sets of subbasins based on different requirements. 
	%		recursive [true] - logical flag to ensure no that no subbasins in the outputs exceed the 'max_basin_size' provided. If 'divide_method' is 
	%			one of the trunk varieties the code will continue redefining trunks and further split subbasins until no extracted basins are greater
	%			than the 'max_basin_size'. If the 'divide_method' is one of the confluence varities, subbasins greater than 'max_basin_size' will simply
	%			no be included in the output. The 'recursive' check is not implemented for the 'order' method.
	% 		threshold_area [1e6] - minimum accumulation area to define streams in meters squared
	% 		segment_length [1000] - smoothing distance in meters for averaging along ksn, suggested value is 1000 meters
	% 		ref_concavity [0.5] - reference concavity for calculating ksn
	% 		write_arc_files [false] - set value to true to output a ascii's of various grids and a shapefile of the ksn, false to not output arc files
	%		s_order [3] - stream order for defining stream outlets for subdividing if 'divide_method' is 'order' (lower number will result in more sub-basins)
	%		min_basin_size [10] - minimum basin size for auto-selecting sub basins. If 'divide_method' is 'filtered_confluences' this value is
	%			interpreted as a minimum drainage area in km^2. If 'divide_method' is 'p_filtered_confluences', this value is interpreted as
	%			the percentage of the input basin drainage area to use as a minimum drainage area, enter a value between 0 and 100 in this case.
	%		no_nested [false] - logical flag that when used in conjunction with either 'filtered_confluences' or 'p_filtered_confluences' will only extract
	%			subbasins if they are the lowest order basin that meets the drainage area requirements (this is to avoid producing nested basins)
	%
	% Examples:
	%		SubdivideBigBasins('/Users/JoeBlow/Project',100,'confluences');
	%		SubdivideBigBasins('/Users/JoeBlow/Project',100,'order','s_order',2,'threshold_area',1e5,'write_arc_files',true);
	%
	% Notes:
	%	-Only the 'order', 'trunk', 'filtered_trunk', and 'p_filtered_trunk' divide methods will not produce nested subbasins.
	% 	-The interpolation necessary to produce a continous ksn grid will fail on extremely small basins. This will not cause the code to fail, but will result in
	%		no 'KsnOBJc' being saved for these basins.
	%	-Methods 'confluences', 'up_confluences', and 'trunk' can result in attempts to extract very small basins. There is an internal check on this that attempts to remove 
	%		these very small basins but it is not always effective and can occassionally result in errors. If you are encountering errors try running the drainage area
	%		filtered versions
	%
	%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
	% Function Written by Adam M. Forte - Updated : 06/18/18 %
	%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

	% Parse Inputs
	p = inputParser;
	p.FunctionName = 'SubDivideBigBasins';
	addRequired(p,'basin_dir',@(x) isdir(x));
	addRequired(p,'max_basin_size',@(x) isnumeric(x));
	addRequired(p,'divide_method',@(x) ischar(validatestring(x,{'order','confluences','up_confluences','filtered_confluences','p_filtered_confluences','trunk','filtered_trunk','p_filtered_trunk'})));

	addParameter(p,'SBFiles_Dir','SubBasins',@(x) ischar(x));
	addParameter(p,'recursive',true,@(x) isscalar(x) && islogical(x));
	addParameter(p,'ref_concavity',0.5,@(x) isscalar(x) && isnumeric(x));
	addParameter(p,'threshold_area',1e6,@(x) isscalar(x) && isnumeric(x));
	addParameter(p,'segment_length',1000,@(x) isscalar(x) && isnumeric(x));
	addParameter(p,'write_arc_files',false,@(x) isscalar(x));
	addParameter(p,'s_order',[3],@(x) isscalar(x));
	addParameter(p,'min_basin_size',[10],@(x) isnumeric(x) & isscalar(x));
	addParameter(p,'no_nested',false,@(x) isscalar(x) && islogical(x));

	parse(p,basin_dir,max_basin_size,divide_method,varargin{:});
	location_of_data_files=p.Results.basin_dir;
	max_basin_size=p.Results.max_basin_size;
	divide_method=p.Results.divide_method;

	SBFiles_Dir=p.Results.SBFiles_Dir;
	recursive=p.Results.recursive;
	theta_ref=p.Results.ref_concavity;
	threshold_area=p.Results.threshold_area;
	segment_length=p.Results.segment_length;
	write_arc_files=p.Results.write_arc_files;
	s_order=p.Results.s_order;
	min_basin_size=p.Results.min_basin_size;
	no_nested=p.Results.no_nested;

	current=pwd;
	cd(location_of_data_files);

	FileList=dir('*Data.mat');
	num_files=numel(FileList);

	% Make Subbasin Directory if it doesn't exist
	if ~isdir(SBFiles_Dir)
		mkdir(SBFiles_Dir);
	end


	if strcmp(divide_method,'p_filtered_confluences') | strcmp(divide_method,'p_filtered_trunk') & min_basin_size>100 | min_basin_size<=0
		error('For divide_method "p_filtered_confluences" the entry to "min_basin_size" must be between 0 and 100')
	end

	% Begin main file loop
	w1=waitbar(0,'Subdividing basins');
	for ii=1:num_files;
		FileName=FileList(ii,1).name;

		% Load in drainage area to check against input
		load(FileName,'drainage_area');
		DA=drainage_area;

		% Check drainage area to determine if this basin will be processed
		if DA>=max_basin_size
			
			% Load in required basin files and rename
			load(FileName,'RiverMouth','DEMoc','DEMcc','FDc','Ac','Sc','ksn_method','gradient_method','radius');
			DEM=DEMoc;
			DEMhc=DEMcc;
			S=Sc;
			FD=FDc;
			A=Ac;
			RM=RiverMouth;	
			basin_num=RM(:,3);

			if strcmp(ksn_method,'trunk')
				load(FileName,'min_order');
			end

			% Peform check on segment length
			if (DEM.cellsize*3)>segment_length
				segment_length=DEM.cellsize*3;
			end

			waitbar(ii/num_files,w1,['Subdividing basin number ' num2str(basin_num) ' - Determining number of subdivisions']);

			DAG=(A.*(A.cellsize^2))/1e6;

			switch divide_method
			case 'order'
				so=streamorder(S);
				if s_order<max(so) 
					Se=modify(S,'streamorder',s_order);
					outs=streampoi(Se,'outlets','xy');
					x=outs(:,1);
					y=outs(:,2);
					num_new_basins=numel(x);
				elseif s_order>=max(so) & max(so)>1
					s_order=s_order-1;
					Se=modify(S,'streamorder',s_order);
					outs=streampoi(Se,'outlets','xy');
					x=outs(:,1);
					y=outs(:,2);
					num_new_basins=numel(x);	
				else
					s_order=max(so);
					Se=modify(S,'streamorder',s_order);
					outs=streampoi(Se,'outlets','xy');
					x=outs(:,1);
					y=outs(:,2);
					num_new_basins=numel(x);
				end			
			case 'confluences'
				S=removeshortstreams(S,DEM.cellsize*10);	
				cons=streampoi(S,'confluences','xy');
				if recursive
					cons_ix=streampoi(S,'confluences','ix');
					idx=DAG.Z(cons_ix)<max_basin_size;
					x=cons(idx,1);
					y=cons(idx,2);
				else
					x=cons(:,1);
					y=cons(:,2);
				end
				num_new_basins=numel(x);
			case 'up_confluences'
				S=removeshortstreams(S,DEM.cellsize*10);
				cons=streampoi(S,'bconfluences','xy');
				if recursive
					cons_ix=streampoi(S,'bconfluences','ix');
					idx=DAG.Z(cons_ix)<max_basin_size;
					x=cons(idx,1);
					y=cons(idx,2);
				else
					x=cons(:,1);
					y=cons(:,2);
				end
				num_new_basins=numel(x);
			case 'filtered_confluences'
				if no_nested
					cons_ix=streampoi(S,'bconfluences','ix');
					if recursive
						da_idx=DAG.Z(cons_ix)>=min_basin_size & DAG.Z(cons_ix)<max_basin_size;
						cons_ix=cons_ix(da_idx);
					else
						da_idx=DAG.Z(cons_ix)>=min_basin_size;
						cons_ix=cons_ix(da_idx);
					end
					[x,y]=CheckUpstream(DEM,FD,cons_ix);
					num_new_basins=numel(x);
				else
					cons_ix=streampoi(S,'confluences','ix');
					cons=streampoi(S,'confluences','xy');
					if recursive
						da_idx=DAG.Z(cons_ix)>=min_basin_size & DAG.Z(cons_ix)<max_basin_size;
					else
						da_idx=DAG.Z(cons_ix)>=min_basin_size;
					end
					cons=cons(da_idx,:);
					x=cons(:,1);
					y=cons(:,2);
					num_new_basins=numel(x);
				end
			case 'p_filtered_confluences'
				if no_nested
					cons_ix=streampoi(S,'bconfluences','ix');
					da_cons=DAG.Z(cons_ix);
					mbz=DA*(min_basin_size/100);
					if recursive
						da_idx=da_cons>=mbz & da_cons<max_basin_size;
					else
						da_idx=da_cons>=mbz;
					end
					[x,y]=CheckUpstream(DEM,FD,cons_ix(da_idx));
					num_new_basins=numel(x);
				else
					cons_ix=streampoi(S,'confluences','ix');
					cons=streampoi(S,'confluences','xy');
					da_cons=DAG.Z(cons_ix);
					mbz=DA*(min_basin_size/100);
					if recursive
						da_idx=da_cons>=mbz & da_cons<max_basin_size;
					else
						da_idx=da_cons>=mbz;
					end
					cons=cons(da_idx,:);
					x=cons(:,1);
					y=cons(:,2);
					num_new_basins=numel(x);
				end
			case 'trunk'
				ST=trunk(klargestconncomps(S,1));
				S=removeshortstreams(S,DEM.cellsize*10);
				tix=streampoi(S,'bconfluences','ix');
				tix=ismember(ST.IXgrid,tix);
				ds=ST.distance;
				ds(~tix)=NaN;
				[~,tix]=max(ds);
				SupT=modify(S,'tributaryto',ST);
				cons=streampoi(SupT,'outlets','xy');
				cons_ix=streampoi(SupT,'outlets','ix');
				cons_ix=vertcat(cons_ix,ST.IXgrid(tix));
				x=cons(:,1); x=vertcat(x,ST.x(tix));
				y=cons(:,2); y=vertcat(y,ST.y(tix));
				num_new_basins=numel(x);

				if recursive
					try
						rec_count=1;
						while any(DAG.Z(cons_ix)>=max_basin_size) & rec_count<=10;
							nidx=DAG.Z(cons_ix)>=max_basin_size;
							if any(nidx)
								x(nidx)=[];
								y(nidx)=[];
								ixs=cons_ix(nidx);
								for jj=1:numel(ixs)
									TIX=GRIDobj(DEM,'logical');
									TIX.Z(ixs(jj))=true;
									S_sub=modify(S,'upstreamto',TIX);
									S_sub=removeshortstreams(S_sub,DEM.cellsize*10);
									ST_sub=trunk(S_sub);
									tix=streampoi(S_sub,'bconfluences','ix');
									tix=ismember(ST_sub.IXgrid,tix);
									ds=ST_sub.distance;
									ds(~tix)=NaN;
									[~,tix]=max(ds);
									SupT_sub=modify(S_sub,'tributaryto',ST_sub);
									cons=streampoi(SupT_sub,'outlets','xy');
									cons_ix=streampoi(SupT_sub,'outlets','ix');
									cons_ix=vertcat(cons_ix,ST_sub.IXgrid(tix));
									xx=cons(:,1); xx=vertcat(xx,ST_sub.x(tix));
									yy=cons(:,2); yy=vertcat(yy,ST_sub.y(tix));
									x=vertcat(x,xx);
									y=vertcat(y,yy);
								end
							end
							rec_count=rec_count+1;
							if rec_count>10
								warning(['Subdivision of basin number ' num2str(basin_num) ' ended prematurely to avoid an infinite loop']);
							end
						end
						num_new_basins=numel(x);
					catch
						warning(['Recursvie subdivision of basin number ' num2str(basin_num) ' failed, proceeding with regular subdivision']);
					end
				end

			case 'filtered_trunk'
				ST=trunk(klargestconncomps(S,1));
				S=removeshortstreams(S,DEM.cellsize*10);
				tix=streampoi(S,'bconfluences','ix');
				tix=ismember(ST.IXgrid,tix);
				ds=ST.distance;
				ds(~tix)=NaN;
				[~,tix]=max(ds);
				SupT=modify(S,'tributaryto',ST);				
				cons_ix=streampoi(SupT,'outlets','ix');
				cons_ix=vertcat(cons_ix,ST.IXgrid(tix));
				cons=streampoi(SupT,'outlets','xy');
				cons=vertcat(cons,[ST.x(tix) ST.y(tix)]);
				da_cons=DAG.Z(cons_ix);
				da_idx=da_cons>=min_basin_size;
				cons=cons(da_idx,:);
				cons_ix=cons_ix(da_idx);
				x=cons(:,1);
				y=cons(:,2);
				num_new_basins=numel(x);

				if recursive
					try
						rec_count=1;
						while any(DAG.Z(cons_ix)>=max_basin_size) & rec_count<=10;
							nidx=DAG.Z(cons_ix)>=max_basin_size;
							if any(nidx)
								x(nidx)=[];
								y(nidx)=[];
								ixs=cons_ix(nidx);
								for jj=1:numel(ixs)
									TIX=GRIDobj(DEM,'logical');
									TIX.Z(ixs(jj))=true;
									S_sub=modify(S,'upstreamto',TIX);
									S_sub=removeshortstreams(S_sub,DEM.cellsize*10);
									ST_sub=trunk(S_sub);
									tix=streampoi(S_sub,'bconfluences','ix');
									tix=ismember(ST_sub.IXgrid,tix);
									ds=ST_sub.distance;
									ds(~tix)=NaN;
									[~,tix]=max(ds);
									SupT_sub=modify(S_sub,'tributaryto',ST_sub);
									cons=streampoi(SupT_sub,'outlets','xy');
									cons_ix=streampoi(SupT_sub,'outlets','ix');
									cons_ix=vertcat(cons_ix,ST_sub.IXgrid(tix));
									xx=cons(:,1); xx=vertcat(xx,ST_sub.x(tix));
									yy=cons(:,2); yy=vertcat(yy,ST_sub.y(tix));
									da_cons=DAG.Z(cons_ix);
									da_idx=da_cons>=min_basin_size;
									x=vertcat(x,xx(da_idx));
									y=vertcat(y,yy(da_idx));
								end
							end
							rec_count=rec_count+1;
							if rec_count>10
								warning(['Subdivision of basin number ' num2str(basin_num) ' ended prematurely to avoid an infinite loop']);
							end						
						end
						num_new_basins=numel(x);
					catch
						warning(['Recursvie subdivision of basin number ' num2str(basin_num) ' failed, proceeding with regular subdivision']);
					end
				end

			case 'p_filtered_trunk'
				ST=trunk(klargestconncomps(S,1));
				S=removeshortstreams(S,DEM.cellsize*10);
				tix=streampoi(S,'bconfluences','ix');
				tix=ismember(ST.IXgrid,tix);
				ds=ST.distance;
				ds(~tix)=NaN;
				[~,tix]=max(ds);
				SupT=modify(S,'tributaryto',ST);
				cons_ix=streampoi(SupT,'confluences','ix');
				cons_ix=vertcat(cons_ix,ST.IXgrid(tix));
				cons=streampoi(SupT,'confluences','xy');
				cons=vertcat(cons,[ST.x(tix) ST.y(tix)]);
				da_cons=DAG.Z(cons_ix);
				mbz=DA*(min_basin_size/100);
				da_idx=da_cons>=mbz;
				cons=cons(da_idx,:);
				cons_ix=cons_ix(da_idx);
				x=cons(:,1);
				y=cons(:,2);
				num_new_basins=numel(x);

				if recursive
					try
						rec_count=1;
						while any(DAG.Z(cons_ix)>=max_basin_size) & rec_count<=10;
							nidx=DAG.Z(cons_ix)>=max_basin_size;
							if any(nidx)
								x(nidx)=[];
								y(nidx)=[];
								ixs=cons_ix(nidx);
								for jj=1:numel(ixs)
									TIX=GRIDobj(DEM,'logical');
									TIX.Z(ixs(jj))=true;
									S_sub=modify(S,'upstreamto',TIX);
									S_sub=removeshortstreams(S_sub,DEM.cellsize*10);
									ST_sub=trunk(S_sub);
									tix=streampoi(S_sub,'bconfluences','ix');
									tix=ismember(ST_sub.IXgrid,tix);
									ds=ST_sub.distance;
									ds(~tix)=NaN;
									[~,tix]=max(ds);
									SupT_sub=modify(S_sub,'tributaryto',ST_sub);
									cons=streampoi(SupT_sub,'outlets','xy');
									cons_ix=streampoi(SupT_sub,'outlets','ix');
									cons_ix=vertcat(cons_ix,ST_sub.IXgrid(tix));
									xx=cons(:,1); xx=vertcat(xx,ST_sub.x(tix));
									yy=cons(:,2); yy=vertcat(yy,ST_sub.y(tix));
									da_cons=DAG.Z(cons_ix);
									da_idx=da_cons>=mbz;
									x=vertcat(x,xx(da_idx));
									y=vertcat(y,yy(da_idx));
								end
							end
							rec_count=rec_count+1;
							if rec_count>10
								warning(['Subdivision of basin number ' num2str(basin_num) ' ended prematurely to avoid an infinite loop']);
							end
						end
						num_new_basins=numel(x);
					catch
						warning(['Recursvie subdivision of basin number ' num2str(basin_num) ' failed, proceeding with regular subdivision']);
					end
				end

			end

			% Nested Waitbar
			w2=waitbar(0,['Processing ' num2str(num_new_basins) ' new basins']);
			pos_w1=get(w1,'position');
			pos_w2=[pos_w1(1) pos_w1(2)-pos_w1(4) pos_w1(3) pos_w1(4)];
			set(w2,'position',pos_w2,'doublebuffer','on');

			waitbar(ii/num_files,w1,['Subdividing basin number ' num2str(basin_num)]);

			for jj=1:num_new_basins
				% waitbar(ii/num_files,w1,['Subdividing basin number ' num2str(basin_num) ' - Processing ' num2str(jj) ' of ' num2str(num_new_basins) ' new basins']);
				
				waitbar(jj/num_new_basins,w2,['Processing ' num2str(jj) ' of ' num2str(num_new_basins) ' new basins']);

				xx=x(jj);
				yy=y(jj);
				basin_string=sprintf([num2str(basin_num) '%03d'],jj);
				RiverMouth=[xx yy str2num(basin_string)];

				% Build dependenc map and clip out drainage basins
				I=dependencemap(FD,xx,yy);
				DEMoc=crop(DEM,I,nan);
				DEMcc=crop(DEMhc,I,nan);
				FDc=crop(FD,I);
				Ac=crop(A,I,nan);

				% Calculate drainage area
				dep_map=GRIDobj2mat(I);
				num_pix=sum(sum(dep_map));
				drainage_area=(num_pix*DEMoc.cellsize*DEMoc.cellsize)/(1e6);

				% Calculate hypsometry
				[rb,eb]=hypscurve(DEMoc,100);
				hyps=[rb eb];

				% Find weighted centroid of drainage basin
				[Cx,Cy]=FindCentroid(DEMoc);
				Centroid=[Cx Cy];

				% Generate new stream map
				Sc=STREAMobj(FDc,'minarea',threshold_area,'unit','mapunits');

				% Check to make sure the stream object isn't empty
				if isempty(Sc.x)
					warning(['Input threshold drainage area is too large for basin ' num2str(RiverMouth(:,3)) ' decreasing threshold area for this basin']);
					new_thresh=threshold_area;
					while isempty(Sc.x)
						new_thresh=new_thresh/2;
						Sc=STREAMobj(FDc,'minarea',new_thresh,'unit','mapunits');
					end
				end

				% Calculate chi and create chi map
				Cc=chitransform(Sc,Ac,'a0',1,'mn',theta_ref);
				ChiOBJc=GRIDobj(DEMoc);
				ChiOBJc.Z(Sc.IXgrid)=Cc;

				% Calculate gradient
				switch gradient_method
				case 'gradient8'
					Goc=gradient8(DEMoc);
				case 'arcslope'
					Goc=arcslope(DEMoc);
				end

				% Find best fit concavity
				SLc=klargestconncomps(Sc,1);
				Chic=chiplot(SLc,DEMcc,Ac,'a0',1,'plot',false);

				% Calculate ksn
				switch ksn_method
				case 'quick'
					[MSc]=KSN_Quick(DEMoc,DEMcc,Ac,Sc,Chic.mn,segment_length);
					[MSNc]=KSN_Quick(DEMoc,DEMcc,Ac,Sc,theta_ref,segment_length);
				case 'trunk'
					[MSc]=KSN_Trunk(DEMoc,DEMcc,Ac,Sc,Chic.mn,segment_length,min_order);
					[MSNc]=KSN_Trunk(DEMoc,DEMcc,Ac,Sc,theta_ref,segment_length,min_order);
				case 'trib'
					% Overide choice if very small basin as KSN_Trib will fail for small basins
					if drainage_area>2.5
						[MSc]=KSN_Trib(DEMoc,DEMcc,FDc,Ac,Sc,Chic.mn,segment_length);
						[MSNc]=KSN_Trib(DEMoc,DEMcc,FDc,Ac,Sc,theta_ref,segment_length);
					else
						[MSc]=KSN_Quick(DEMoc,DEMcc,Ac,Sc,Chic.mn,segment_length);
						[MSNc]=KSN_Quick(DEMoc,DEMcc,Ac,Sc,theta_ref,segment_length);
					end
				end

				% Calculate basin wide ksn statistics
				min_ksn=min([MSNc.ksn],[],'omitnan');
				mean_ksn=mean([MSNc.ksn],'omitnan');
				max_ksn=max([MSNc.ksn],[],'omitnan');
				std_ksn=std([MSNc.ksn],'omitnan');
				se_ksn=std_ksn/sqrt(numel(MSNc)); % Standard error

				% Calculate basin wide gradient statistics
				min_grad=min(Goc.Z(:),[],'omitnan');
				mean_grad=mean(Goc.Z(:),'omitnan');
				max_grad=max(Goc.Z(:),[],'omitnan');
				std_grad=std(Goc.Z(:),'omitnan');
				se_grad=std_grad/sqrt(sum(~isnan(Goc.Z(:)))); % Standard error

				% Calculate basin wide elevation statistics
				min_z=min(DEMoc.Z(:),[],'omitnan');
				mean_z=mean(DEMoc.Z(:),'omitnan');
				max_z=max(DEMoc.Z(:),[],'omitnan');
				std_z=std(DEMoc.Z(:),'omitnan');
				se_z=std_z/sqrt(sum(~isnan(DEMoc.Z(:)))); % Standard error

				KSNc_stats=[mean_ksn se_ksn std_ksn min_ksn max_ksn];
				Gc_stats=double([mean_grad se_grad std_grad min_grad max_grad]);
				Zc_stats=double([mean_z se_z std_z min_z max_z]);

				% Find outlet elevation
				out_ix=coord2ind(DEMoc,xx,yy);
				out_el=double(DEMoc.Z(out_ix));

				SubFileName=[SBFiles_Dir '/Basin_' num2str(basin_num) '_DataSubset_' num2str(jj) '.mat'];

				save(SubFileName,'RiverMouth','DEMcc','DEMoc','out_el','drainage_area','hyps','FDc','Ac','Sc','SLc','Chic','Goc','MSc','MSNc','KSNc_stats','Gc_stats','Zc_stats','Centroid','ChiOBJc','ksn_method','gradient_method','theta_ref','-v7.3');

				if strcmp(ksn_method,'trunk')
					save(SubFileName,'min_order','-append');
				end
				
				% Make interpolated ksn grid
				if ~isempty(radius)
					try 
						[KsnOBJc] = KsnAvg(DEMoc,MSNc,radius);
						save(SubFileName,'KsnOBJc','radius','-append');
					catch
						warning(['Interpolation of KSN grid failed for basin ' num2str(RiverMouth(:,3))]);
						save(SubFilename,'radius','-append');
					end
				else
					save(SubFileName,'radius','-append');
				end

				VarList=whos('-file',FileName);
				VarInd=find(strcmp(cellstr(char(VarList.name)),'AGc'));

				if ~isempty(VarInd)
					load(FileName,'AGc');
					AG=AGc;
					num_grids=size(AG,1);
					AGc=cell(size(AG));
					for kk=1:num_grids
						AGcOI=crop(AG{kk,1},I,nan);
						AGc{kk,1}=AGcOI;
						AGc{kk,2}=AG{kk,2};
						mean_AGc=mean(AGcOI.Z(:),'omitnan');
						min_AGc=min(AGcOI.Z(:),[],'omitnan');
						max_AGc=max(AGcOI.Z(:),[],'omitnan');
						std_AGc=std(AGcOI.Z(:),'omitnan');
						se_AGc=std_AGc/sqrt(sum(~isnan(AGcOI.Z(:))));
						AGc_stats(kk,:)=[mean_AGc se_AGc std_AGc min_AGc max_AGc];
					end
					save(SubFileName,'AGc','AGc_stats','-append');
				end

				VarInd=find(strcmp(cellstr(char(VarList.name)),'ACGc'));
				if ~isempty(VarInd)
					load(FileName,'ACGc');
					ACG=ACGc;
					num_grids=size(ACG,1);
					ACGc=cell(size(ACG));
					for kk=1:num_grids
						ACGcOI=crop(ACG{kk,1},I,nan);
						ACGc{kk,1}=ACGcOI;
						ACGc{kk,3}=ACG{kk,3};
						edg=ACG{kk,2}.Numbers;
						edg=edg+0.5;
						edg=vertcat(0.5,edg);
						[N,~]=histcounts(ACGcOI.Z(:),edg);
						T=ACG{kk,2};
						T.Counts=N';
						ACGc{kk,2}=T;
						ACGc_stats(kk,1)=[mode(ACGcOI.Z(:))];
					end
					save(SubFileName,'ACGc','ACGc_stats','-append');	
				end	

				VarInd=find(strcmp(cellstr(char(VarList.name)),'rlf'));
				if ~isempty(VarInd)
					load(FileName,'rlf');
					rlf_full=rlf; 
					num_rlf=size(rlf_full,1);
					rlf=cell(size(rlf_full));
					rlf_stats=zeros(num_rlf,6);
					for kk=1:num_rlf
						% Calculate relief
						radOI=rlf_full{kk,2};
						rlf{kk,2}=radOI;
						rlfOI=localtopography(DEMoc,radOI);
						rlf{kk,1}=rlfOI;
						% Calculate stats
						mean_rlf=mean(rlfOI.Z(:),'omitnan');
						min_rlf=min(rlfOI.Z(:),[],'omitnan');
						max_rlf=max(rlfOI.Z(:),[],'omitnan');
						std_rlf=std(rlfOI.Z(:),'omitnan');
						se_rlf=std_rlf/sqrt(sum(~isnan(rlfOI.Z(:))));
						rlf_stats(kk,:)=[mean_rlf se_rlf std_rlf min_rlf max_rlf radOI];
					end
					save(SubFileName,'rlf','rlf_stats','-append');
				end					

				if write_arc_files
					% Replace NaNs in DEM with -32768
					Didx=isnan(DEMoc.Z);
					DEMoc_temp=DEMoc;
					DEMoc_temp.Z(Didx)=-32768;

					DEMFileName=[SBFiles_Dir '/Basin_' num2str(basin_num) '_DataSubset_' num2str(jj) '_DEM.txt'];
					GRIDobj2ascii(DEMoc_temp,DEMFileName);
					CHIFileName=[SBFiles_Dir '/Basin_' num2str(basin_num) '_DataSubset_' num2str(jj) '_CHI.txt'];
					GRIDobj2ascii(ChiOBJc,CHIFileName);
					KSNFileName=[SBFiles_Dir '/Basin_' num2str(basin_num) '_DataSubset_' num2str(jj) '_KSN.shp'];
					shapewrite(MSNc,KSNFileName);

					if calc_relief
						for kk=1:num_rlf
							RLFFileName=[SBFiles_Dir '/Basin_' num2str(basin_num) '_DataSubset_' num2str(jj) '_RLF_' num2str(rlf{kk,2}) '.txt'];
							GRIDobj2ascii(rlf{kk,1},RLFFileName);
						end
					end

					if ~isempty(AG);
						for kk=1:num_grids
							AGcFileName=[SBFiles_Dir '/Basin_' num2str(basin_num) '_DataSubset_' num2str(jj) '_' AGc{kk,2} '.txt'];
							GRIDobj2ascii(AGc{kk,1},AGcFileName);
						end
					end

					if ~isempty(ACG);
						for jj=1:num_grids
							ACGcFileName=[SBFiles_Dir '/Basin_' num2str(basin_num) '_' ACGc{jj,3} '.txt'];
							GRIDobj2ascii(ACGc{jj,1},ACGcFileName);
						end
					end
				end
			end % New basin loop end
			close(w2);
		end % Drainage Area check end
	end % Main Loop end
	close(w1);
	cd(current);
end % Main Function End

function [ksn_ms]=KSN_Quick(DEM,DEMc,A,S,theta_ref,segment_length)
	g=gradient(S,DEMc);
	G=GRIDobj(DEM);
	G.Z(S.IXgrid)=g;

	Z_RES=DEMc-DEM;

	ksn=G./(A.*(A.cellsize^2)).^(-theta_ref);

	SD=GRIDobj(DEM);
	SD.Z(S.IXgrid)=S.distance;
	
	ksn_ms=STREAMobj2mapstruct(S,'seglength',segment_length,'attributes',...
		{'ksn' ksn @mean 'uparea' (A.*(A.cellsize^2)) @mean 'gradient' G @mean 'cut_fill' Z_RES @mean...
		'min_dist' SD @min 'max_dist' SD @max});

	seg_dist=[ksn_ms.max_dist]-[ksn_ms.min_dist];
	distcell=num2cell(seg_dist');
	[ksn_ms(1:end).seg_dist]=distcell{:};
	ksn_ms=rmfield(ksn_ms,{'min_dist','max_dist'});
end

function [ksn_ms]=KSN_Trunk(DEM,DEMc,A,S,theta_ref,segment_length,min_order)

	order_exp=['>=' num2str(min_order)];

    Smax=modify(S,'streamorder',order_exp);
	Smin=modify(S,'rmnodes',Smax);

	g=gradient(S,DEMc);
	G=GRIDobj(DEM);
	G.Z(S.IXgrid)=g;

	Z_RES=DEMc-DEM;

	ksn=G./(A.*(A.cellsize^2)).^(-theta_ref);

	SDmax=GRIDobj(DEM);
	SDmin=GRIDobj(DEM);
	SDmax.Z(Smax.IXgrid)=Smax.distance;
	SDmin.Z(Smin.IXgrid)=Smin.distance;

	ksn_ms_min=STREAMobj2mapstruct(Smin,'seglength',segment_length,'attributes',...
		{'ksn' ksn @mean 'uparea' (A.*(A.cellsize^2)) @mean 'gradient' G @mean 'cut_fill' Z_RES @mean...
		'min_dist' SDmin @min 'max_dist' SDmin @max});

	ksn_ms_max=STREAMobj2mapstruct(Smax,'seglength',segment_length,'attributes',...
		{'ksn' ksn @mean 'uparea' (A.*(A.cellsize^2)) @mean 'gradient' G @mean 'cut_fill' Z_RES @mean...
		'min_dist' SDmax @min 'max_dist' SDmax @max});

	ksn_ms=vertcat(ksn_ms_min,ksn_ms_max);
	seg_dist=[ksn_ms.max_dist]-[ksn_ms.min_dist];
	distcell=num2cell(seg_dist');
	[ksn_ms(1:end).seg_dist]=distcell{:};
	ksn_ms=rmfield(ksn_ms,{'min_dist','max_dist'});
end

function [ksn_ms]=KSN_Trib(DEM,DEMc,FD,A,S,theta_ref,segment_length)

	% Define non-intersecting segments
	[as]=networksegment_slim(DEM,FD,S);
	seg_bnd_ix=as.ix;
	% Precompute values or extract values needed for later
	z=getnal(S,DEMc);
	zu=getnal(S,DEM);
	z_res=z-zu;
	g=gradient(S,DEMc);
	c=chitransform(S,A,'a0',1,'mn',theta_ref);
	d=S.distance;
	da=getnal(S,A.*(A.cellsize^2));
	ixgrid=S.IXgrid;
	% Extract ordered list of stream indices and find breaks between streams
	s_node_list=S.orderednanlist;
	streams_ix=find(isnan(s_node_list));
	streams_ix=vertcat(1,streams_ix);
	% Generate empty node attribute list for ksn values
	ksn_nal=zeros(size(d));
	% Begin main loop through channels
	num_streams=numel(streams_ix)-1;
	seg_count=1;
	for ii=1:num_streams
		% Extract node list for stream of interest
		if ii==1
			snlOI=s_node_list(streams_ix(ii):streams_ix(ii+1)-1);
		else
			snlOI=s_node_list(streams_ix(ii)+1:streams_ix(ii+1)-1);
		end

		% Determine which segments are within this stream
		[~,~,dn]=intersect(snlOI,seg_bnd_ix(:,1));
		[~,~,up]=intersect(snlOI,seg_bnd_ix(:,2));
		seg_ix=intersect(up,dn);

		num_segs=numel(seg_ix);
		dn_up=seg_bnd_ix(seg_ix,:);
		for jj=1:num_segs
			% Find positions within node list
			dnix=find(snlOI==dn_up(jj,1));
			upix=find(snlOI==dn_up(jj,2));
			% Extract segment indices of desired segment
			seg_ix_oi=snlOI(upix:dnix);
			% Extract flow distances and normalize
			dOI=d(seg_ix_oi);
			dnOI=dOI-min(dOI);
			num_bins=ceil(max(dnOI)/segment_length);
			bin_edges=[0:segment_length:num_bins*segment_length];
			% Loop through bins
			for kk=1:num_bins
				idx=dnOI>bin_edges(kk) & dnOI<=bin_edges(kk+1);
				bin_ix=seg_ix_oi(idx);
				cOI=c(bin_ix);
				zOI=z(bin_ix);
				if numel(cOI)>2
					[ksn_val,r2]=Chi_Z_Spline(cOI,zOI);
					ksn_nal(bin_ix)=ksn_val;

					% Build mapstructure
					ksn_ms(seg_count).Geometry='Line';
					ksm_ms(seg_count).BoundingBox=[min(S.x(bin_ix)),min(S.y(bin_ix));max(S.x(bin_ix)),max(S.y(bin_ix))];
					ksn_ms(seg_count).X=S.x(bin_ix);
					ksn_ms(seg_count).Y=S.y(bin_ix);
					ksn_ms(seg_count).ksn=ksn_val;
					ksn_ms(seg_count).uparea=mean(da(bin_ix));
					ksn_ms(seg_count).gradient=mean(g(bin_ix));
					ksn_ms(seg_count).cut_fill=mean(z_res(bin_ix));
					ksn_ms(seg_count).seg_dist=max(S.distance(bin_ix))-min(S.distance(bin_ix));
					ksn_ms(seg_count).chi_r2=r2;
					
					seg_count=seg_count+1;
				end
			end
		end
	end
end

function seg = networksegment_slim(DEM,FD,S)
	% Slimmed down version of 'networksegment' from main TopoToolbox library that also removes zero and single node length segments

	%% Identify channel heads, confluences, b-confluences and outlets
	Vhead = streampoi(S,'channelheads','logical');  ihead=find(Vhead==1);  IXhead=S.IXgrid(ihead);
	Vconf = streampoi(S,'confluences','logical');   iconf=find(Vconf==1);  IXconf=S.IXgrid(iconf);
	Vout = streampoi(S,'outlets','logical');        iout=find(Vout==1);    IXout=S.IXgrid(iout);
	Vbconf = streampoi(S,'bconfluences','logical'); ibconf=find(Vbconf==1);IXbconf=S.IXgrid(ibconf);

	%% Identify basins associated to b-confluences and outlets
	DB   = drainagebasins(FD,vertcat(IXbconf,IXout));DBhead=DB.Z(IXhead); DBbconf=DB.Z(IXbconf); DBconf=DB.Z(IXconf); DBout=DB.Z(IXout);

	%% Compute flowdistance
	D = flowdistance(FD);

	%% Identify river segments
	% links between channel heads and b-confluences
	[~,ind11,ind12]=intersect(DBbconf,DBhead);
	% links between confluences and b-confluences
	[~,ind21,ind22]=intersect(DBbconf,DBconf);
	% links between channel heads and outlets
	[~,ind31,ind32]=intersect(DBout,DBhead);
	% links between channel heads and outlets
	[~,ind41,ind42]=intersect(DBout,DBconf);
	% Connecting links into segments
	IX(:,1) = [ IXbconf(ind11)' IXbconf(ind21)' IXout(ind31)'  IXout(ind41)'  ];   ix(:,1)= [ ibconf(ind11)' ibconf(ind21)' iout(ind31)'  iout(ind41)'  ];
	IX(:,2) = [ IXhead(ind12)'  IXconf(ind22)'  IXhead(ind32)' IXconf(ind42)' ];   ix(:,2)= [ ihead(ind12)'  iconf(ind22)'  ihead(ind32)' iconf(ind42)' ];

	% Compute segment flow length
	flength=double(abs(D.Z(IX(:,1))-D.Z(IX(:,2))));

	% Remove zero and one node length elements
	idx=flength>=2*DEM.cellsize;
	seg.IX=IX(idx,:);
	seg.ix=ix(idx,:);
	seg.flength=flength(idx);

	% Number of segments
	seg.n=numel(IX(:,1));
	end

function [KSN,R2] = Chi_Z_Spline(c,z)

	% Resample chi-elevation relationship using cubic spline interpolation
	[~,minIX]=min(c);
	zb=z(minIX);
	chiF=c-min(c);
	zabsF=z-min(z);
	chiS=linspace(0,max(chiF),numel(chiF)).';
	zS=spline(chiF,zabsF,chiS);

	% Calculate ksn via slope
	KSN= chiS\(zS); % mn not needed because a0 is fixed to 1

	% Calculate R^2
	z_pred=chiF.*KSN;
	sstot=sum((zabsF-mean(zabsF)).^2);
	ssres=sum((zabsF-z_pred).^2);
	R2=1-(ssres/sstot);

end

function [KSNGrid] = KsnAvg(DEM,ksn_ms,radius)

	% Calculate radius
	radiuspx = ceil(radius/DEM.cellsize);

	% Record mask of current NaNs
	MASK=isnan(DEM.Z);

	% Make grid with values along channels
	KSNGrid=GRIDobj(DEM);
	KSNGrid.Z(:,:)=NaN;
	for ii=1:numel(ksn_ms)
		ix=coord2ind(DEM,ksn_ms(ii).X,ksn_ms(ii).Y);
		KSNGrid.Z(ix)=ksn_ms(ii).ksn;
	end

	% Local mean based on radius
	ISNAN=isnan(KSNGrid.Z);
    [~,L] = bwdist(~ISNAN,'e');
    ksng = KSNGrid.Z(L);           
    FLT   = fspecial('disk',radiuspx);
    ksng   = imfilter(ksng,FLT,'symmetric','same','conv');

    % Set original NaN cells back to NaN
    ksng(MASK)=NaN;

    % Output
    KSNGrid.Z=ksng;
end

function [x,y] = CheckUpstream(DEM,FD,ix)
	% Build cell of influence list
	inflcs=cell(numel(ix),1);
	for ii=1:numel(ix)
	    IX=influencemap(FD,ix(ii));
	    inflcs{ii}=find(IX.Z);
	end
	    
	% Build index
	idx=zeros(numel(ix),1);
	idx=logical(idx);
	for ii=1:numel(ix)
	    inflcs_temp=inflcs;
	    inflcs_temp{ii}=[0];
	    up_member=cellfun(@(x) ismember(ix(ii),x),inflcs_temp);
	    if any(up_member)
	        idx(ii)=false;
	    else
	        idx(ii)=true;
	    end
	end

	[x,y]=ind2coord(DEM,ix(idx));
end