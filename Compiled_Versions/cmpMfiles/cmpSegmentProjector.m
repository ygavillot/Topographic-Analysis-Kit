function cmpSegmentProjector(wdir,MatFile,varargin);
	% Description:
	% 	Function to interactively select segments of a channel profile you wish to project (e.g. projecting a portion of the profile with a different ksn).
	%	You can use the 'cmpSegmentPicker' function to interactively choose channels to provide to the StreamProjector function. If the STREAMobj has more than 
	%	one channel head, this code will iterate through all channel heads (i.e. make sure you're only providing it stream you want to project, not an entire
	%	network!). It calculates and will display 95% confidence bounds on this fit.
	%	
	% Required Inputs:
	%	wdir - full path of working directory
	%	MatFile - Name of matfile output from either 'cmpMakeStreams' or the name of a single basin mat file from 'cmpProcessRiverBasins'
	%
	% Optional Inputs:
	%	file_name_prefix ['sel'] - prefix for outputs	
	%	conditioned_DEM [] - option to provide name of a hydrologically conditioned DEM for use in this function, expects the mat file as saved by 
	%		'cmpConditionDEM'. See 'cmpConditionDEM' function for options for making a hydrological conditioned DEM. If no input is provided the code defaults 
	%		to using the mincosthydrocon function.
	%	new_stream_net [] - option to provide name of a matfile containing a new stream network as as output from another function (e.g. SegmentPicker) to use
	%		instead of the stream network saved in the MatFile provided to the function. This new stream network must have been generated from the
	%		DEM stored in the provided MatFile
	%	concavity_method ['ref']- options for concavity
	%		'ref' - uses a reference concavity, the user can specify this value with the reference concavity option (see below)
	%		'auto' - function finds a best fit concavity for the provided stream
	%	pick_method ['chi'] - choice of how you want to pick the stream segment to be projected:
	%		'chi' - select segments on a chi - z plot
	%		'stream' - select segments on a longitudinal profile
	%	ref_concavity [0.50] - refrence concavity used if 'theta_method' is set to 'auto'
	%	refit_streams [false] - option to recalculate chi based on the concavity of the picked segment (true), useful if you want to try to precisely 
	%		match the shape of the picked segment of the profile. Only used if 'theta_method' is set to 'auto'
	%	save_figures [false] - option to save (if set to true) figures at the end of the projection process
	%	interp_value [0.1] - value (between 0 and 1) used for interpolation parameter in mincosthydrocon (not used if user provides a conditioned DEM)
	%
	% Output:
	%	Projected_Channel_Heads.txt - 2 column text file containing the x and y coordinates of channel heads of projected channels
	%	Projected_Channel_*.txt - 10 column text file for each projected channel containing the x coordinate, y coordinate, drainage area, chi value,
	%		concavity, true elevation, projected elevation, postive uncertainty on projected elevation, and negative uncertainty on projected elevation.
	%
   	% Examples if running for the command line, minus OS specific way of calling main TAK function:
    %   SegmentProjector /path/to/wdir Topo.mat 
    %   SegmentProjector /path/to/wdir Topo.mat new_stream_net ThresholdStreams.mat pick_method stream
	%
	%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
	% Function Written by Adam M. Forte - Updated : 07/02/18 %
	%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
	if isdeployed
		if ~isempty(varargin)
			varargin=varargin{1};
		end
	end

	% Parse Inputs
	p = inputParser;
	p.FunctionName = 'cmpSegmentProjector';
	addRequired(p,'wdir',@(x) ischar(x));
	addRequired(p,'MatFile',@(x) regexp(x,regexptranslate('wildcard','*.mat')));

	addParameter(p,'file_name_prefix','sel',@(x) ischar(x));
	addParameter(p,'concavity_method','ref',@(x) ischar(validatestring(x,{'ref','auto'})));
	addParameter(p,'pick_method','chi',@(x) ischar(validatestring(x,{'chi','stream'})));
	addParameter(p,'smooth_distance',1000,@(x) isscalar(x) && isnumeric(x));
	addParameter(p,'ref_concavity',0.50,@(x) isscalar(x) && isnumeric(x));
	addParameter(p,'refit_streams',false,@(x) isscalar(x) && islogical(x));
	addParameter(p,'save_figures',false,@(x) isscalar(x) && islogical(x));
	addParameter(p,'conditioned_DEM',[],@(x) regexp(x,regexptranslate('wildcard','*.mat')));
	addParameter(p,'new_stream_net',[],@(x) regexp(x,regexptranslate('wildcard','*.mat')));
	addParameter(p,'interp_value',0.1,@(x) isnumeric(x) && x>=0 && x<=1);

	parse(p,wdir,MatFile,varargin{:});
	wdir=p.Results.wdir;
	MatFile=p.Results.MatFile;

	file_name_prefix=p.Results.file_name_prefix;
	smooth_distance=p.Results.smooth_distance;
	theta_method=p.Results.concavity_method;
	ref_theta=p.Results.ref_concavity;
	refit_streams=p.Results.refit_streams;
	pick_method=p.Results.pick_method;
	save_figures=p.Results.save_figures;
	iv=p.Results.interp_value;
	DEMc=p.Results.conditioned_DEM;
	nsn=p.Results.new_stream_net;


	% Determine the type of input
	MatFile=fullfile(wdir,MatFile);
	D=whos('-file',MatFile);
	VL=cell(numel(D),1);
	for ii=1:numel(D);
		VL{ii}=D(ii,1).name;
	end

	if any(strcmp(VL,'DEM')) & any(strcmp(VL,'FD')) & any(strcmp(VL,'A')) & any(strcmp(VL,'S'))
		load(MatFile,'DEM','FD','A','S');
	elseif any(strcmp(VL,'DEMoc')) & any(strcmp(VL,'FDc')) & any(strcmp(VL,'Ac')) & any(strcmp(VL,'Sc'))
		load(MatFile,'DEMoc','FDc','Ac','Sc');
		DEM=DEMoc;
		FD=FDc;
		A=Ac;
		S=Sc;
	end	

	if ~isempty(nsn)
		nsn=fullfile(wdir,nsn);
		SD=whos('-file',nsn);
		VS=cell(numel(SD),1);
		for ii=1:numel(SD)
			VS{ii}=SD(ii,1).name;
		end

		if any(strcmp(VS,'Sn'))
			load(nsn,'Sn');
			S=Sn;
		elseif any(strcmp(VS,'Sc'))
			load(nsn,'Sc');
			S=Sc;
		elseif any(strcmp(VS,'S'));
			load(nsn,'S');
		end

		if ~validatealignment(S,DEM)
			error('Supplied new stream net does not appear to have been generated from the same DEM supplied to the function');
		end
	end

	% Hydrologically condition dem
	if isempty(DEMc)
		zc=mincosthydrocon(S,DEM,'interp',iv);
		DEMc=GRIDobj(DEM);
		DEMc.Z(DEMc.Z==0)=NaN;
		DEMc.Z(S.IXgrid)=zc;
	else
		DEMc=fullfile(wdir,DEMc);
		load(DEMc,'DEMc');
		if ~validatealignment(DEMc,DEM)
			error('Provided conditioned DEM does not appear to align with the original DEM')
		end
	end

	% Find channel heads
	ST=S;
	chix=streampoi(ST,'channelheads','ix');
	num_ch=numel(chix);

	% Parse Switches
	if strcmp(theta_method,'ref') & strcmp(pick_method,'chi');
		method=1;
	elseif strcmp(theta_method,'auto') & strcmp(pick_method,'chi');
		method=2;
	elseif strcmp(theta_method,'ref') & strcmp(pick_method,'stream');
		method=3;
	elseif strcmp(theta_method,'auto') & strcmp(pick_method,'stream');
		method=4;
	end

	close all

	OUT=cell(2,num_ch);

	% Set string input
	str1='N';

	switch method
	case 1
		% Autocalculate ksn for comparison purposes
		[auto_ksn]=KSN_Quick(DEM,A,ST,ref_theta);

		for ii=1:num_ch
			CHIX=GRIDobj(DEM);
			CHIX.Z(chix(ii))=1; CHIX.Z=logical(CHIX.Z);
			S=modify(ST,'downstreamto',CHIX);

			C=ChiCalc(S,DEMc,A,1,ref_theta);

			ak=getnal(S,auto_ksn);
			[DAvg,KsnAvg]=BinAverage(S.distance,ak,smooth_distance);
			[~,CAvg]=BinAverage(C.distance,C.chi,smooth_distance);

			f1=figure(1);
			set(f1,'Units','normalized','Position',[0.05 0.1 0.45 0.8],'renderer','painters');

			clf
			subplot(3,1,3);
			hold on
			pl1=plotdz(S,DEM,'dunit','km','Color',[0.5 0.5 0.5]);
			pl2=plotdz(S,DEMc,'dunit','km','Color','k');
			xlabel('Distance from Mouth (km)')
			ylabel('Elevation (m)')
			legend([pl1 pl2],'Unconditioned DEM','Conditioned DEM','location','best');
			title('Long Profile')
			hold off

			ax2=subplot(3,1,2);
			hold on
			scatter(CAvg,KsnAvg,20,'k','filled');
			xlabel('Chi')
			ylabel('Auto k_{sn}');
			title('Chi - Auto k_{sn}');
			hold off

			ax1=subplot(3,1,1);
			hold on
			plot(C.chi,C.elev,'-k');
			scatter(C.chi,C.elev,10,'k');
			xlabel('\chi','Color','r')
			ylabel('Elevation (m)','Color','r')
			title(['\chi - Z : \theta = ' num2str(C.mn) ' : Select bounds of stream segment you want to project'],'Color','r')
			ax1.XColor='Red';
			ax1.YColor='Red';
			hold off

			linkaxes([ax1,ax2],'x');

			while strcmpi(str1,'N')
				[cv,e]=ginput(2);

				% Sort knickpoint list and construct bounds list
				cvs=sortrows(cv);

				rc=C.chi;
				rx=C.x;
				ry=C.y;
				re=C.elev;

				lb=cvs(1);
				rb=cvs(2);

				% Clip out stream segment
				lb_chidist=sqrt(sum(bsxfun(@minus, rc, lb).^2,2));
				rb_chidist=sqrt(sum(bsxfun(@minus, rc, rb).^2,2));

				[~,lbix]=min(lb_chidist);
				[~,rbix]=min(rb_chidist);

				rcC=rc(rbix:lbix);
				reC=re(rbix:lbix);

				hold on
				p1=scatter(ax1,rcC,reC,20,'r','filled');
				hold off


	            qa=questdlg('Is this the stream segment you wanted to project?','Stream Projection','No','Yes','Yes');
	            switch qa
	            case 'Yes'
	                str1 = 'Y';
	            case 'No'
	                str1 = 'N';
	            end

				delete(p1);
			end

			f=fit(rcC,reC,'poly1');
			cf=coeffvalues(f);
			ci=confint(f);
			ksn=cf(1);
			eint=cf(2);
			ksnl=ci(1,1);
			ksnu=ci(2,1);
			eintl=ci(1,2);
			eintu=ci(2,2);

			pred_el=(rc.*ksn)+eint;
			pred_el_u=(rc.*ksnl)+eintu;
			pred_el_l=(rc.*ksnu)+eintl;

			subplot(3,1,1)
			hold on
			plot(C.chi,pred_el,'-r','LineWidth',2);
			plot(C.chi,pred_el_u,'--r');
			plot(C.chi,pred_el_l,'--r');
			hold off

			subplot(3,1,3)
			hold on
			pl3=plot(C.distance./1000,pred_el,'-r','LineWidth',2);
			pl4=plot(C.distance./1000,pred_el_u,'--r');
			plot(C.distance./1000,pred_el_l,'--r');
			legend([pl1 pl2 pl3 pl4],'Unconditioned DEM','Conditioned DEM','Projected Stream','Uncertainty','location','best');
			hold off

			f2=figure(2);
			set(f2,'Units','normalized','Position',[0.5 0.1 0.45 0.8],'renderer','painters');
			subplot(2,1,1)
			hold on
			plot([0,max(C.chi)],[0,0],'--k');
			scatter(C.chi,pred_el-C.elev,10,'k')
			xlabel('\chi');
			ylabel('Difference between projection and true profile (m)')
			hold off

			subplot(2,1,2)
			hold on
			plot([0,max(C.distance)/1000],[0,0],'--k');
			scatter(C.distance./1000,pred_el-C.elev,10,'k')
			xlabel('Distance (km)');
			ylabel('Difference between projection and true profile (m)')
			hold off

			[chx,chy]=ind2coord(DEM,chix(ii));
			OUT{1,ii}=[chx chy];
			OUT{2,ii}=[C.x C.y C.distance C.area C.chi ones(size(C.chi)).*C.mn C.elev pred_el pred_el_u pred_el_l];

			if save_figures
				print(f1,'-dpdf',fullfile(wdir,[file_name_prefix '_ProjectedProfile_' num2str(ii) '.pdf']),'-bestfit');
				print(f2,'-dpdf',fullfile(wdir,[file_name_prefix '_Residual_' num2str(ii) '.pdf']),'-bestfit');
			else
				if ii<num_ch
					uiwait(msgbox('Click OK when ready to continue'))
				end
			end

			if ii<num_ch
				close(f1);
				close(f2);
			end

			% Reset string
			str1='N';
		end
	case 2
		for ii=1:num_ch
			CHIX=GRIDobj(DEM);
			CHIX.Z(chix(ii))=1; CHIX.Z=logical(CHIX.Z);
			S=modify(ST,'downstreamto',CHIX);

			C=ChiCalc(S,DEMc,A,1);

			% Autocalculate ksn for comparison purposes
			[auto_ksn]=KSN_Quick(DEM,A,S,C.mn);
			ak=getnal(S,auto_ksn);
			[DAvg,KsnAvg]=BinAverage(S.distance,ak,smooth_distance);
			[~,CAvg]=BinAverage(C.distance,C.chi,smooth_distance);

			f1=figure(1);
			set(f1,'Units','normalized','Position',[0.05 0.1 0.45 0.8],'renderer','painters');

			clf
			subplot(3,1,3);
			hold on
			pl1=plotdz(S,DEM,'dunit','km','Color',[0.5 0.5 0.5]);
			pl2=plotdz(S,DEMc,'dunit','km','Color','k');
			xlabel('Distance from Mouth (km)')
			ylabel('Elevation (m)')
			legend([pl1 pl2],'Unconditioned DEM','Conditioned DEM','location','best');
			title('Long Profile')
			hold off

			ax2=subplot(3,1,2);
			hold on
			scatter(CAvg,KsnAvg,20,'k','filled');
			xlabel('\chi')
			ylabel('Auto k_{sn}');
			title('\chi - Auto k_{sn}');
			hold off

			ax1=subplot(3,1,1);
			hold on
			plot(C.chi,C.elev,'-k');
			scatter(C.chi,C.elev,10,'k');
			xlabel('\chi','Color','r')
			ylabel('Elevation (m)','Color','r')
			title(['\chi - Z : \theta = ' num2str(C.mn) ' : Select bounds of stream segment you want to project'],'Color','r')
			hold off

			linkaxes([ax1,ax2],'x');

			switch refit_streams
			case false

				while strcmpi(str1,'N')
					[cv,e]=ginput(2);

					% Sort knickpoint list and construct bounds list
					cvs=sortrows(cv);

					rc=C.chi;
					rx=C.x;
					ry=C.y;
					re=C.elev;

					lb=cvs(1);
					rb=cvs(2);

					% Clip out stream segment
					lb_chidist=sqrt(sum(bsxfun(@minus, rc, lb).^2,2));
					rb_chidist=sqrt(sum(bsxfun(@minus, rc, rb).^2,2));

					[~,lbix]=min(lb_chidist);
					[~,rbix]=min(rb_chidist);

					rcC=rc(rbix:lbix);
					reC=re(rbix:lbix);

					hold on
					p1=scatter(ax1,rcC,reC,20,'r','filled');
					hold off

		            qa=questdlg('Is this the stream segment you wanted to project?','Stream Projection','No','Yes','Yes');
		            switch qa
		            case 'Yes'
		                str1 = 'Y';
		            case 'No'
		                str1 = 'N';
		            end

					delete(p1);
				end

				f=fit(rcC,reC,'poly1');
				cf=coeffvalues(f);
				ci=confint(f);
				ksn=cf(1);
				eint=cf(2);
				ksnl=ci(1,1);
				ksnu=ci(2,1);
				eintl=ci(1,2);
				eintu=ci(2,2);

				pred_el=(rc.*ksn)+eint;
				pred_el_u=(rc.*ksnl)+eintu;
				pred_el_l=(rc.*ksnu)+eintl;

				subplot(3,1,1)
				hold on
				pl3=plot(C.chi,pred_el,'-r','LineWidth',2);
				pl4=plot(C.chi,pred_el_u,'--r');
				plot(C.chi,pred_el_l,'--r');
				legend([pl1 pl2 pl3 pl4],'Unconditioned DEM','Conditioned DEM','Projected Stream','Uncertainty','location','best');
				hold off

				subplot(3,1,3)
				hold on
				plot(C.distance./1000,pred_el,'-r','LineWidth',2);
				plot(C.distance./1000,pred_el_u,'--r');
				plot(C.distance./1000,pred_el_l,'--r');
				hold off

				f2=figure(2);
				set(f2,'Units','normalized','Position',[0.5 0.1 0.45 0.8],'renderer','painters');
				subplot(2,1,1)
				hold on
				plot([0,max(C.chi)],[0,0],'--k');
				scatter(C.chi,pred_el-C.elev,10,'k')
				xlabel('\chi');
				ylabel('Difference between projection and true profile (m)')
				hold off

				subplot(2,1,2)
				hold on
				plot([0,max(C.distance)/1000],[0,0],'--k');
				scatter(C.distance./1000,pred_el-C.elev,10,'k')
				xlabel('Distance (km)');
				ylabel('Difference between projection and true profile (m)')
				hold off

				[chx,chy]=ind2coord(DEM,chix(ii));
				OUT{1,ii}=[chx chy];
				OUT{2,ii}=[C.x C.y C.distance C.area C.chi ones(size(C.chi)).*C.mn C.elev pred_el pred_el_u pred_el_l];

			case true

				while strcmpi(str1,'N')
					[cv,e]=ginput(2);

					% Sort knickpoint list and construct bounds list
					cvs=sortrows(cv);

					rc0=C.chi;
					rx0=C.x;
					ry0=C.y;
					re0=C.elev;

					lb=cvs(1);
					rb=cvs(2);

					% Clip out stream segment
					lb_chidist=sqrt(sum(bsxfun(@minus, rc0, lb).^2,2));
					rb_chidist=sqrt(sum(bsxfun(@minus, rc0, rb).^2,2));

					[~,lbix]=min(lb_chidist);
					[~,rbix]=min(rb_chidist);

					% Clip out stream segment
					lbx=rx0(lb_chidist==min(lb_chidist));
					lby=ry0(lb_chidist==min(lb_chidist));

					rbx=rx0(rb_chidist==min(rb_chidist));
					rby=ry0(rb_chidist==min(rb_chidist));	

					lix=coord2ind(DEM,lbx,lby);
					LIX=GRIDobj(DEM);
					LIX.Z(lix)=1;
					[lixmat,X,Y]=GRIDobj2mat(LIX);
					lixmat=logical(lixmat);
					LIX=GRIDobj(X,Y,lixmat);	

					rix=coord2ind(DEM,rbx,rby);
					RIX=GRIDobj(DEM);
					RIX.Z(rix)=1;
					[rixmat,X,Y]=GRIDobj2mat(RIX);
					rixmat=logical(rixmat);
					RIX=GRIDobj(X,Y,rixmat);	

					Seg=modify(S,'downstreamto',RIX);
					Seg=modify(Seg,'upstreamto',LIX);

					% Find stream segment concavity
					Csegrf=ChiCalc(Seg,DEMc,A,1);

					% Recalculate chi over entire stream with new concavity
					CN=ChiCalc(S,DEMc,A,1,Csegrf.mn);
					rc=CN.chi;
					rx=CN.x;
					ry=CN.y;
					re=CN.elev;

					rcC0=rc0(rbix:lbix);
					reC0=re0(rbix:lbix);

					rcC=rc(rbix:lbix);
					reC=re(rbix:lbix);

					hold on
					p1=scatter(ax1,rcC0,reC0,20,'r','filled');
					hold off

		            qa=questdlg('Is this the stream segment you wanted to project?','Stream Projection','No','Yes','Yes');
		            switch qa
		            case 'Yes'
		                str1 = 'Y';
		            case 'No'
		                str1 = 'N';
		            end

					delete(p1);
				end

				% Autocalculate ksn for comparison purposes
				[auto_ksn]=KSN_Quick(DEM,A,S,Csegrf.mn);
				ak=getnal(S,auto_ksn);
				[DAvg,KsnAvg]=BinAverage(S.distance,ak,smooth_distance);
				[~,CAvg]=BinAverage(CN.distance,CN.chi,smooth_distance);

				f=fit(rcC,reC,'poly1');
				cf=coeffvalues(f);
				ci=confint(f);
				ksn=cf(1);
				eint=cf(2);
				ksnl=ci(1,1);
				ksnu=ci(2,1);
				eintl=ci(1,2);
				eintu=ci(2,2);

				pred_el=(rc.*ksn)+eint;
				pred_el_u=(rc.*ksnl)+eintu;
				pred_el_l=(rc.*ksnu)+eintl;

				f1=figure(1);
				clf; cla;
				set(f1,'Units','normalized','Position',[0.05 0.1 0.45 0.8],'renderer','painters');

				ax1=subplot(3,1,1);
				hold on
				plot(CN.chi,CN.elev,'-k');
				scatter(CN.chi,CN.elev,10,'k');
				plot(CN.chi,pred_el,'-r','LineWidth',2);
				plot(CN.chi,pred_el_u,'--r');
				plot(CN.chi,pred_el_l,'--r');
				xlabel('\chi')
				ylabel('Elevation (m)')
				title(['\chi - Z : \theta = ' num2str(CN.mn)],'Color','r')
				hold off

				ax2=subplot(3,1,2);
				hold on
				scatter(CAvg,KsnAvg,20,'k','filled');
				xlabel('Chi')
				ylabel('Auto k_{sn}');
				title('Chi - Auto k_{sn}');
				hold off

				subplot(3,1,3)
				hold on
				pl1=plotdz(S,DEM,'dunit','km','Color',[0.5 0.5 0.5]);
				pl2=plotdz(S,DEMc,'dunit','km','Color','k');
				pl3=plot(CN.distance./1000,pred_el,'-r','LineWidth',2);
				pl4=plot(CN.distance./1000,pred_el_u,'--r');
				plot(CN.distance./1000,pred_el_l,'--r');
				xlabel('Distance from Mouth (km)')
				ylabel('Elevation (m)')
				legend([pl1 pl2 pl3 pl4],'Unconditioned DEM','Conditioned DEM','Projected Stream','Uncertainty','location','best');
				title('Long Profile')
				hold off	

				linkaxes([ax1,ax2],'x');

				f2=figure(2);
				set(f2,'Units','normalized','Position',[0.5 0.1 0.45 0.8],'renderer','painters');
				subplot(2,1,1)
				hold on
				plot([0,max(CN.chi)],[0,0],'--k');
				scatter(CN.chi,pred_el-CN.elev,10,'k')
				xlabel('\chi');
				ylabel('Difference between projection and true profile (m)')
				hold off

				subplot(2,1,2)
				hold on
				plot([0,max(CN.distance)/1000],[0,0],'--k');
				scatter(CN.distance./1000,pred_el-CN.elev,10,'k')
				xlabel('Distance (km)');
				ylabel('Difference between projection and true profile (m)')
				hold off

				[chx,chy]=ind2coord(DEM,chix(ii));
				OUT{1,ii}=[chx chy];
				OUT{2,ii}=[CN.x CN.y CN.distance CN.area CN.chi ones(size(CN.chi)).*CN.mn CN.elev pred_el pred_el_u pred_el_l];

			end


			if save_figures
				print(f1,'-dpdf',fullfile(wdir,[file_name_prefix '_ProjectedProfile_' num2str(ii) '.pdf']),'-bestfit');
				print(f2,'-dpdf',fullfile(wdir,[file_name_prefix '_Residual_' num2str(ii) '.pdf']),'-bestfit');
			else
				if ii<num_ch
					uiwait(msgbox('Click OK when ready to continue'))
				end
			end

			if ii<num_ch
				close(f1);
				close(f2);
			end

			% Reset output string 1
			str1='N';
		end
	case 3
		% Autocalculate ksn for comparison purposes
		[auto_ksn]=KSN_Quick(DEM,A,ST,ref_theta);

		for ii=1:num_ch
			CHIX=GRIDobj(DEM);
			CHIX.Z(chix(ii))=1; CHIX.Z=logical(CHIX.Z);
			S=modify(ST,'downstreamto',CHIX);

			C=ChiCalc(S,DEMc,A,1,ref_theta);

			ak=getnal(S,auto_ksn);
			[DAvg,KsnAvg]=BinAverage(S.distance,ak,smooth_distance);

			f1=figure(1);
			set(f1,'Units','normalized','Position',[0.05 0.1 0.45 0.8],'renderer','painters');

			clf

			subplot(3,1,1);
			hold on
			plot(C.chi,C.elev,'-k');
			scatter(C.chi,C.elev,10,'k');
			xlabel('\chi')
			ylabel('Elevation (m)')
			title('\chi - Z')
			hold off

			ax2=subplot(3,1,2);
			hold on
			scatter(DAvg./1000,KsnAvg,20,'k','filled');
			xlabel('Distance (km)')
			ylabel('Auto k_{sn}');
			title('\chi - Auto k_{sn}');
			hold off

			ax1=subplot(3,1,3);
			hold on
			pl1=plotdz(S,DEM,'dunit','km','Color',[0.5 0.5 0.5]);
			pl2=plotdz(S,DEMc,'dunit','km','Color','k');
			xlabel('Distance from Mouth (km)','Color','r')
			ylabel('Elevation (m)','Color','r')
			legend([pl1 pl2],'Unconditioned DEM','Conditioned DEM','location','best');
			title(['Long Profile : \theta = ' num2str(C.mn) ' : Select bounds of stream segment you want to project'],'Color','r')
			ax1.XColor='Red';
			ax1.YColor='Red';
			hold off

			linkaxes([ax1,ax2],'x');

			while strcmpi(str1,'N')
				[d,e]=ginput(2);
				d=d*1000;

				% Sort knickpoint list and construct bounds list
				ds=sortrows(d);

				rd=C.distance;
				rx=C.x;
				ry=C.y;
				rc=C.chi;
				re=C.elev;

				lb=ds(1);
				rb=ds(2);

				lb_dist=sqrt(sum(bsxfun(@minus, rd, lb).^2,2));
				rb_dist=sqrt(sum(bsxfun(@minus, rd, rb).^2,2));

				[~,lbix]=min(lb_dist);
				[~,rbix]=min(rb_dist);

				rcC=rc(rbix:lbix);
				reC=re(rbix:lbix);
				rdC=rd(rbix:lbix);

				hold on
				p1=scatter(ax1,rdC/1000,reC,20,'r','filled');
				hold off

	            qa=questdlg('Is this the stream segment you wanted to project?','Stream Projection','No','Yes','Yes');
	            switch qa
	            case 'Yes'
	                str1 = 'Y';
	            case 'No'
	                str1 = 'N';
	            end

				delete(p1);
			end				

			f=fit(rcC,reC,'poly1');
			cf=coeffvalues(f);
			ci=confint(f);
			ksn=cf(1);
			eint=cf(2);
			ksnl=ci(1,1);
			ksnu=ci(2,1);
			eintl=ci(1,2);
			eintu=ci(2,2);

			pred_el=(rc.*ksn)+eint;
			pred_el_u=(rc.*ksnl)+eintu;
			pred_el_l=(rc.*ksnu)+eintl;

			subplot(3,1,1)
			hold on
			plot(C.chi,pred_el,'-r','LineWidth',2);
			plot(C.chi,pred_el_u,'--r');
			plot(C.chi,pred_el_l,'--r');
			hold off

			subplot(3,1,3)
			hold on
			pl3=plot(C.distance./1000,pred_el,'-r','LineWidth',2);
			pl4=plot(C.distance./1000,pred_el_u,'--r');
			plot(C.distance./1000,pred_el_l,'--r');
			legend([pl1 pl2 pl3 pl4],'Unconditioned DEM','Conditioned DEM','Projected Stream','Uncertainty','location','best');
			hold off

			f2=figure(2);
			set(f2,'Units','normalized','Position',[0.5 0.1 0.45 0.8],'renderer','painters');
			subplot(2,1,1)
			hold on
			plot([0,max(C.chi)],[0,0],'--k');
			scatter(C.chi,pred_el-C.elev,10,'k')
			xlabel('\chi');
			ylabel('Difference between projection and true profile (m)')
			hold off

			subplot(2,1,2)
			hold on
			plot([0,max(C.distance)/1000],[0,0],'--k');
			scatter(C.distance./1000,pred_el-C.elev,10,'k')
			xlabel('Distance (km)');
			ylabel('Difference between projection and true profile (m)')
			hold off

			[chx,chy]=ind2coord(DEM,chix(ii));
			OUT{1,ii}=[chx chy];
			OUT{2,ii}=[C.x C.y C.distance C.area C.chi ones(size(C.chi)).*C.mn C.elev pred_el pred_el_u pred_el_l];

			if save_figures
				print(f1,'-dpdf',fullfile(wdir,[file_name_prefix '_ProjectedProfile_' num2str(ii) '.pdf']),'-bestfit');
				print(f2,'-dpdf',fullfile(wdir,[file_name_prefix '_Residual_' num2str(ii) '.pdf']),'-bestfit');
			else
				if ii<num_ch
					uiwait(msgbox('Click OK when ready to continue'))
				end
			end

			if ii<num_ch
				close(f1);
				close(f2);
			end

			% Reset string
			str1='N';
		end

	case 4
		for ii=1:num_ch
			CHIX=GRIDobj(DEM);
			CHIX.Z(chix(ii))=1; CHIX.Z=logical(CHIX.Z);
			S=modify(ST,'downstreamto',CHIX);

			C=ChiCalc(S,DEMc,A,1);

			% Autocalculate ksn for comparison purposes
			[auto_ksn]=KSN_Quick(DEM,A,S,C.mn);
			ak=getnal(S,auto_ksn);
			[DAvg,KsnAvg]=BinAverage(S.distance,ak,smooth_distance);

			f1=figure(1);
			set(f1,'Units','normalized','Position',[0.05 0.1 0.45 0.8],'renderer','painters');

			clf

			subplot(3,1,1);
			hold on
			plot(C.chi,C.elev,'-k');
			scatter(C.chi,C.elev,10,'k');
			xlabel('\chi')
			ylabel('Elevation (m)')
			title('\chi - Z')
			hold off

			ax2=subplot(3,1,2);
			hold on
			scatter(DAvg./1000,KsnAvg,20,'k','filled');
			xlabel('Distance (km)')
			ylabel('Auto k_{sn}');
			title('\chi - Auto k_{sn}');
			hold off

			ax1=subplot(3,1,3);
			hold on
			pl1=plotdz(S,DEM,'dunit','km','Color',[0.5 0.5 0.5]);
			pl2=plotdz(S,DEMc,'dunit','km','Color','k');
			xlabel('Distance from Mouth (km)','Color','r')
			ylabel('Elevation (m)','Color','r')
			legend([pl1 pl2],'Unconditioned DEM','Conditioned DEM','location','best');
			title(['Long Profile : \theta = ' num2str(C.mn) ' : Select bounds of stream segment you want to project'],'Color','r')
			hold off

			linkaxes([ax1,ax2],'x');

			switch refit_streams
			case false

				while strcmpi(str1,'N')
					[d,e]=ginput(2);
					d=d*1000;

					% Sort knickpoint list and construct bounds list
					ds=sortrows(d);

					rd=C.distance;
					rx=C.x;
					ry=C.y;
					rc=C.chi;
					re=C.elev;

					lb=ds(1);
					rb=ds(2);

					lb_dist=sqrt(sum(bsxfun(@minus, rd, lb).^2,2));
					rb_dist=sqrt(sum(bsxfun(@minus, rd, rb).^2,2));

					[~,lbix]=min(lb_dist);
					[~,rbix]=min(rb_dist);

					rcC=rc(rbix:lbix);
					reC=re(rbix:lbix);
					rdC=rd(rbix:lbix);

					hold on
					p1=scatter(ax1,rdC/1000,reC,20,'r','filled');
					hold off

		            qa=questdlg('Is this the stream segment you wanted to project?','Stream Projection','No','Yes','Yes');
		            switch qa
		            case 'Yes'
		                str1 = 'Y';
		            case 'No'
		                str1 = 'N';
		            end

					delete(p1);
				end

				f=fit(rcC,reC,'poly1');
				cf=coeffvalues(f);
				ci=confint(f);
				ksn=cf(1);
				eint=cf(2);
				ksnl=ci(1,1);
				ksnu=ci(2,1);
				eintl=ci(1,2);
				eintu=ci(2,2);

				pred_el=(rc.*ksn)+eint;
				pred_el_u=(rc.*ksnl)+eintu;
				pred_el_l=(rc.*ksnu)+eintl;

				subplot(3,1,1)
				hold on
				plot(C.chi,pred_el,'-r','LineWidth',2);
				plot(C.chi,pred_el_u,'--r');
				plot(C.chi,pred_el_l,'--r');
				hold off

				subplot(3,1,3)
				hold on
				pl3=plot(C.distance./1000,pred_el,'-r','LineWidth',2);
				pl4=plot(C.distance./1000,pred_el_u,'--r');
				plot(C.distance./1000,pred_el_l,'--r');
				legend([pl1 pl2 pl3 pl4],'Unconditioned DEM','Conditioned DEM','Projected Stream','Uncertainty','location','best');
				hold off

				f2=figure(2);
				set(f2,'Units','normalized','Position',[0.5 0.1 0.45 0.8],'renderer','painters');
				subplot(2,1,1)
				hold on
				plot([0,max(C.chi)],[0,0],'--k');
				scatter(C.chi,pred_el-C.elev,10,'k')
				xlabel('\chi');
				ylabel('Difference between projection and true profile (m)')
				hold off

				subplot(2,1,2)
				hold on
				plot([0,max(C.distance)/1000],[0,0],'--k');
				scatter(C.distance./1000,pred_el-C.elev,10,'k')
				xlabel('Distance (km)');
				ylabel('Difference between projection and true profile (m)')
				hold off

				[chx,chy]=ind2coord(DEM,chix(ii));
				OUT{1,ii}=[chx chy];
				OUT{2,ii}=[C.x C.y C.distance C.area C.chi ones(size(C.chi)).*C.mn C.elev pred_el pred_el_u pred_el_l];

			case true

				while strcmpi(str1,'N')
					[d,e]=ginput(2);
					d=d*1000;

					% Sort knickpoint list and construct bounds list
					ds=sortrows(d);

					rd=C.distance;
					rx=C.x;
					ry=C.y;
					rc=C.chi;
					re=C.elev;

					lb=ds(1);
					rb=ds(2);

					lb_dist=sqrt(sum(bsxfun(@minus, rd, lb).^2,2));
					rb_dist=sqrt(sum(bsxfun(@minus, rd, rb).^2,2));

					[~,lbix]=min(lb_dist);
					[~,rbix]=min(rb_dist);

					lbx=rx(lb_dist==min(lb_dist));
					lby=ry(lb_dist==min(lb_dist));

					rbx=rx(rb_dist==min(rb_dist));
					rby=ry(rb_dist==min(rb_dist));	

					lix=coord2ind(DEM,lbx,lby);
					LIX=GRIDobj(DEM);
					LIX.Z(lix)=1;
					[lixmat,X,Y]=GRIDobj2mat(LIX);
					lixmat=logical(lixmat);
					LIX=GRIDobj(X,Y,lixmat);	

					rix=coord2ind(DEM,rbx,rby);
					RIX=GRIDobj(DEM);
					RIX.Z(rix)=1;
					[rixmat,X,Y]=GRIDobj2mat(RIX);
					rixmat=logical(rixmat);
					RIX=GRIDobj(X,Y,rixmat);	

					Seg=modify(S,'downstreamto',RIX);
					Seg=modify(Seg,'upstreamto',LIX);

					Csegrf=ChiCalc(Seg,DEMc,A,1);

					CN=ChiCalc(S,DEMc,A,1,Csegrf.mn);

					rc=CN.chi;
					rx=CN.x;
					ry=CN.y;
					re=CN.elev;

					rcC=rc(rbix:lbix);
					reC=re(rbix:lbix);
					rdC=rd(rbix:lbix);

					hold on
					p1=scatter(ax1,rdC/1000,reC,20,'r','filled');
					hold off

		            qa=questdlg('Is this the stream segment you wanted to project?','Stream Projection','No','Yes','Yes');
		            switch qa
		            case 'Yes'
		                str1 = 'Y';
		            case 'No'
		                str1 = 'N';
		            end

					delete(p1);
				end

				% Autocalculate ksn for comparison purposes
				[auto_ksn]=KSN_Quick(DEM,A,S,Csegrf.mn);
				ak=getnal(S,auto_ksn);
				[DAvg,KsnAvg]=BinAverage(S.distance,ak,smooth_distance);
				[~,CAvg]=BinAverage(CN.distance,CN.chi,smooth_distance);

				f=fit(rcC,reC,'poly1');
				cf=coeffvalues(f);
				ci=confint(f);
				ksn=cf(1);
				eint=cf(2);
				ksnl=ci(1,1);
				ksnu=ci(2,1);
				eintl=ci(1,2);
				eintu=ci(2,2);

				pred_el=(rc.*ksn)+eint;
				pred_el_u=(rc.*ksnl)+eintu;
				pred_el_l=(rc.*ksnu)+eintl;

				f1=figure(1);
				clf; cla;
				set(f1,'Units','normalized','Position',[0.05 0.1 0.45 0.8],'renderer','painters');

				subplot(3,1,1);
				hold on
				plot(CN.chi,CN.elev,'-k');
				scatter(CN.chi,CN.elev,10,'k');
				plot(CN.chi,pred_el,'-r','LineWidth',2);
				plot(CN.chi,pred_el_u,'--r');
				plot(CN.chi,pred_el_l,'--r');
				xlabel('\chi')
				ylabel('Elevation (m)')
				title('\chi - Z')
				hold off

				ax2=subplot(3,1,2);
				hold on
				scatter(DAvg./1000,KsnAvg,20,'k','filled');
				xlabel('Distance (km)')
				ylabel('Auto k_{sn}');
				title('Chi - Auto k_{sn}');
				hold off

				ax1=subplot(3,1,3);
				hold on
				pl1=plotdz(S,DEM,'dunit','km','Color',[0.5 0.5 0.5]);
				pl2=plotdz(S,DEMc,'dunit','km','Color','k');
				pl3=plot(CN.distance./1000,pred_el,'-r','LineWidth',2);
				pl4=plot(CN.distance./1000,pred_el_u,'--r');
				plot(CN.distance./1000,pred_el_l,'--r');
				xlabel('Distance from Mouth (km)')
				ylabel('Elevation (m)')
				legend([pl1 pl2 pl3 pl4],'Unconditioned DEM','Conditioned DEM','Projected Stream','Uncertainty','location','best');
				title(['Long Profile : \theta = ' num2str(CN.mn)],'Color','r')
				hold off	

				linkaxes([ax1,ax2],'x');

				f2=figure(2);
				set(f2,'Units','normalized','Position',[0.5 0.1 0.45 0.8],'renderer','painters');
				subplot(2,1,1)
				hold on
				plot([0,max(CN.chi)],[0,0],'--k');
				scatter(CN.chi,pred_el-CN.elev,10,'k')
				xlabel('\chi');
				ylabel('Difference between projection and true profile (m)')
				hold off

				subplot(2,1,2)
				hold on
				plot([0,max(CN.distance)/1000],[0,0],'--k');
				scatter(CN.distance./1000,pred_el-CN.elev,10,'k')
				xlabel('Distance (km)');
				ylabel('Difference between projection and true profile (m)')
				hold off

				[chx,chy]=ind2coord(DEM,chix(ii));
				OUT{1,ii}=[chx chy];
				OUT{2,ii}=[CN.x CN.y CN.distance CN.area CN.chi ones(size(CN.chi)).*CN.mn CN.elev pred_el pred_el_u pred_el_l];
			end

			if save_figures
				print(f1,'-dpdf',fullfile(wdir,[file_name_prefix '_ProjectedProfile_' num2str(ii) '.pdf']),'-bestfit');
				print(f2,'-dpdf',fullfile(wdir,[file_name_prefix '_Residual_' num2str(ii) '.pdf']),'-bestfit');
			else
				if ii<num_ch
					uiwait(msgbox('Click OK when ready to continue'))
				end
			end

			if ii<num_ch
				close(f1);
				close(f2);
			end

			str1='N';
		end
	end

	% Parse and save outputs
	ch_list=OUT(1,:);
	ch_list=vertcat(ch_list{:});
	chT=table;
	chT.channel_heads_x=ch_list(:,1);
	chT.channel_heads_y=ch_list(:,2);
	writetable(chT,fullfile(wdir,[file_name_prefix '_Projected_Channel_Heads.txt']));

	proj_ch=OUT(2,:);
	for ii=1:numel(proj_ch)
		fout_name=fullfile(wdir,[file_name_prefix '_Projected_Channel_' num2str(ii) '.txt']);
		projD=proj_ch{ii};
		projT=table;
		projT.x_coord=projD(:,1);
		projT.y_coord=projD(:,2);
		projT.distance=projD(:,3);
		projT.area=projD(:,4);
		projT.chi=projD(:,5);
		projT.concavity=projD(:,6);
		projT.true_elevation=projD(:,7);
		projT.proj_elevation=projD(:,8);
		projT.posUncert=projD(:,9);
		projT.negUncert=projD(:,10);
		writetable(projT,fout_name);
		clear projT;
	end

	save(fullfile(wdir,[file_name_prefix '_Projected_Channels.mat']),'OUT');

	close(f1);
	close(f2);

end

function [OUT]=ChiCalc(S,DEM,A,a0,varargin)
% Modified version of chiplot function by Wolfgang Schwanghart to remove unused options/outputs and 
% to interpolate chi-z relationship so that chi values are equally spaced to avoid biasing of ksn fit
% by clustering at high drainage areas 

mnmethod='ls'; % Similar switch for calculating best fit concavity (if reference not provided)

% nr of nodes in the entire stream network
nrc = numel(S.x);
M   = sparse(double(S.ix),double(S.ixc),true,nrc,nrc);
% find outlet
outlet = sum(M,2) == 0 & sum(M,1)'~=0;
if nnz(outlet)>1
    % there must not be more than one outlet (constraint could be removed
    % in the future).
    error('The stream network must not have more than one outlet');
end


% elevation values at nodes
zx   = double(DEM.Z(S.IXgrid));
% elevation at outlet
zb   = double(DEM.Z(S.IXgrid(outlet)));
% a is the term inside the brackets of equation 6b 
a    = double(a0./(A.Z(S.IXgrid)*(A.cellsize.^2)));
% x is the cumulative horizontal distance in upstream direction
x    = S.distance;
Lib = true(size(x));

% Find bestfit concavity if no concavity provided or use provided concavity
if isempty(varargin)
    mn0  = 0.5; % initial value
    mn   = fminsearch(@mnfit,mn0);
else
	mn=varargin{1};
end

% calculate chi
chi = netcumtrapz(x,a.^mn,S.ix,S.ixc);

% Resample chi-elevation relationship using cubic spline interpolation
chiF=chi(Lib);
zabsF=zx(Lib)-zb;

chiS=linspace(0,max(chiF),numel(chiF)).';
zS=spline(chiF,zabsF,chiS);

% Calculate ksn
ksn = chiS\(zS);

OUT=struct;
OUT.ks   = ksn;
OUT.mn   = mn;
[OUT.x,...
 OUT.y,...
 OUT.chi,...
 OUT.elev,...
 OUT.elevbl,...
 OUT.distance,...
 OUT.pred,...
 OUT.area] = STREAMobj2XY(S,chi,DEM,zx-zb,S.distance,ksn*chi,A.*(A.cellsize^2));
 OUT.res = OUT.elevbl - OUT.pred;

	% Nested function for calculating mn ratio
	function sqres = mnfit(mn)
		% calculate chi with a given mn ratio
		% and integrate in upstream direction
		CHI = netcumtrapz(x(Lib),a(Lib).^mn,S.ix,S.ixc);%*ab.^mn
		% normalize both variables
		CHI = CHI ./ max(CHI);
		z   = zx(Lib)-zb;
		z   = z./max(z);
        switch mnmethod
            case 'ls' % least squares
                sqres = sum((CHI - z).^2);
            case 'lad' % least absolute devation
                sqres = sum(sqrt(abs(CHI-z)));
        end
	end

end

function z = netcumtrapz(x,y,ix,ixc)
% cumtrapz along upward direction in a directed tree network

z = zeros(size(x));
for lp = numel(ix):-1:1;
    z(ix(lp)) = z(ixc(lp)) + (y(ixc(lp))+(y(ix(lp))-y(ixc(lp)))/2) *(abs(x(ixc(lp))-x(ix(lp))));
end
end

function [Xavg,Yavg]=BinAverage(X,Y,bin_size);

	ix=~isnan(X);
	X=X(ix); Y=Y(ix);

	minX=min(X);
	maxX=max(X);

	b=[minX:bin_size:maxX+bin_size];

	try
		[~,~,idx]=histcounts(X,b);
	catch
		[~,idx]=histc(X,b);
	end

	Xavg=accumarray(idx(:),X,[],@mean);
	Yavg=accumarray(idx(:),Y,[],@mean);
end

function [ksn]=KSN_Quick(DEM,A,S,theta_ref)

	zc=mincosthydrocon(S,DEM,'interp',0.1);
	DEMc=GRIDobj(DEM);
	DEMc.Z(DEMc.Z==0)=NaN;
	DEMc.Z(S.IXgrid)=zc;
	G=gradient8(DEMc);

	ksn=G./(A.*(A.cellsize^2)).^(-theta_ref);
	
end
