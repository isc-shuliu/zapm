Include %ZAPM.ext.Common

/// installation string ZPM, ZAPM, Registry
/// set $namespace="%SYS", name="DefaultSSL" do:'##class(Security.SSLConfigs).Exists(name) ##class(Security.SSLConfigs).Create(name) set url="https://pm.community.intersystems.com/packages/zpm/latest/installer" Do ##class(%Net.URLParser).Parse(url,.comp) set ht = ##class(%Net.HttpRequest).%New(), ht.Server = comp("host"), ht.Port = 443, ht.Https=1, ht.SSLConfiguration=name, st=ht.Get(comp("path")) quit:'st $System.Status.GetErrorText(st) set xml=##class(%File).TempFilename("xml"), tFile = ##class(%Stream.FileBinary).%New(), tFile.Filename = xml do tFile.CopyFromAndSave(ht.HttpResponse.Data) do ht.%Close(), $system.OBJ.Load(xml,"ck") do ##class(%File).Delete(xml) zpm "install zapm" zapm "newdb zpm-registry" zapm "zna"
/// research and development ZPM
Class %ZAPM.ext.zpm [ Abstract ]
{

Parameter VERSION = "1.0.25";

/// Storage of work history
Parameter GN = "^%ZAPM.ZpmLoad";

/// Storage of settings
Parameter GNSET = "^%ZAPM.settings";

/// do ##class(%ZAPM.ext.zpm).LoadRegistrys()
/// do ##class(%ZAPM.ext.zpm).LoadRegistrys("c*",1)
/// do ##class(%ZAPM.ext.zpm).LoadRegistrys(,,,"iris-csv-anonymizer")
ClassMethod LoadRegistrys(modulename = "", all = 0, skipZPM = 1, StartingFrom = "") As %Status
{
	set currns=$namespace
	set gn=..#GN
	do ##class(%ZAPM.ext.zpm).GetVerZpm(.IsHspm,.RepoFieldName)	
	set sql="select Name, Version, "_RepoFieldName_", Description from %ZPM_PackageManager_Developer.Utils_GetModuleList('registry') "_$s(modulename="":"",modulename["*":"where Name like '"_$tr(modulename,"*","%")_"'",1:"where Name=?")
		,rs=##class(%ResultSet).%New()
		,sc=rs.Prepare(sql)
	set:sc sc=rs.Execute($zconvert(modulename,"L"))
	write !,sql
	if sc {
		for i=1:1 {
			quit:'rs.%Next()  
			set name=rs.Get("Name")

			if $g(Starting)="",StartingFrom'="" {
				i (("@"_name)'[("@"_StartingFrom)) write !,name," Skip" continue
				set Starting=1
			}
			
			set Version=rs.Get("Version")
			set Repo=rs.Get(RepoFieldName)
			set ns=$zconvert($tr(name,"_$.","-S"),"U")
			if skipZPM, name["apptools"||(name="zpm")||($e(name,1,4)="zpm-")||(name["appmsw")||($e(name,1,4)="zapm") w !,"Skip "_$$$escGreen(name) continue
			if $d(@gn@(name)) { ;already load
				if $d(@gn@(name,"install")) { ;restore
					;set @gn@(name,"generate")=##class(apptools.core.code).SetList(@gn@(name,"generate"), 1, ns)
					;set @gn@(name,"install")=##class(apptools.core.code).SetList(@gn@(name,"install"), 3, Version)
					;set @gn@(name,"install")=##class(apptools.core.code).SetList(@gn@(name,"install"), 4, Repo)
					;set @gn@(name,"url")="<a target='_blank' href='"_Repo_"'>"_Repo_"</a>"
					if $lg(@gn@(name,"install"),3)'=Version {
						write !,"Upgrade "_$$$escGreen(name)_" to new version: "_$$$escRed(Version)
						do ..InstallModule(name, ns, Version, Repo, gn, .err)
					}
					if $lg(@gn@(name,"install"),2)'=$$$OK {
						write !,$$$escGreen(name)_" Last error: "_$$$escRed($lg(@gn@(name,"install"),1))
						w !!," ReInstall ? Y\N\Q" Read R   quit:R="Q"||(R="q")
						do:R["y" ..InstallModule(name, ns, Version, Repo, gn, .err)
					}
				}
				if $lg($g(@gn@(name,"generate")),2)'=""||($lg($g(@gn@(name,"install")),1)'="") {
					;					
					if 0 {
						write !,ns_" Unload Removed DBNS ? Y\N " Read R   quit:"q"[R
						if $g(R)="y" {
							do ##class(%ZAPM.ext.zpm).UnloadAndDeleteDBNS(name,Version,Repo,gn)
							kill @gn@(name)
						}
						continue
					}
				}
				write !,"Already loaded - Skip "_$$$escGreen(name)
			} elseif 1 {
				set sta=##class(%ZPM.PackageManager).Shell("find -r -d "_name) write !
				if 'sta s err=$System.Status.GetErrorText(sta) w !,err w !,"Skip" continue
				if 'all w !!," Load into a new database ("_ns_") ? Y\N " Read R   quit:"q"[R
				if $g(R)="y"||(all=1) {
					do ##class(%ZAPM.ext.zpm).CreateDBNSAndLoad(name,ns,Version,Repo,gn,.error)
					if $g(error)["<INTERRUPT>" quit
				}
			}
		}
	}
	write !,"Log in global ",!,gn
}

/// do ##class(%ZAPM.ext.zpm).ShowLog()
/// do ##class(%ZAPM.ext.zpm).ShowLog("d:\_proj\!\zapm.log")
ClassMethod ShowLog(fn = "") As %Status
{
	set gn=..#GN
	set name=""
	if fn'="" if ##class(apptools.core.files).OpenFile(fn) 
	for { set name=$o(@gn@(name)) quit:name=""
		if '$d(@gn@(name,"install")) {
			if fn'="" use fn write !,!,name,!,"   ошибка инсталляции, нет "_$zr use 0 continue
			write !,$$$escGreen(name)_"   ошибка инсталляции, нет "_$zr
			;do ##class(%ZAPM.ext.zpm).LoadRegistrys(name) 
			continue
		}
		set st=$lg(@gn@(name,"install"),2)
		if 'st {
			if fn'="" use fn write !,!,name,!,"   "_$System.Status.GetErrorText(st) use 0 continue
			write !,$$$escGreen(name),"   ",$$$escRed($System.Status.GetErrorText(st))
		}
	}
	if fn'="" close fn
}

/// extention zpm commands
/// do ##class(%ZAPM.ext.zpm).extcmd("load https://github.com/Vassil2010/iris-sms")
/// zapp "newdb spool-demo"
ClassMethod extcmd(cmd = "") As %Status
{
	if $lf($lb("find","search"),$p(cmd," ")) quit ##class(%ZAPM.ext.zpm).find($p(cmd," ",2,*)_" ")
	if $p(cmd," ")="help" quit ##class(%ZAPM.ext.zpm).help($p(cmd," ",2,*))
	if $p(cmd," ")="newdb" {
		set cmdext=$p(cmd," ",2,*)
		if cmd["zpm ""install " set cmdext=$p($p(cmd,"zpm ""install ",2,*),$c(34))
		quit ##class(%ZAPM.ext.zpm).CreateDBNSAndLoad(cmdext)
	}

	if $p(cmd," ")="load" quit ##class(%ZAPM.ext.zpm).LoadFromRepo($p(cmd," ",2,*))
	if $p(cmd," ")="ver" {
		zpm "ver" 
		write !,$$$FormattedLine($$$Underlined,$$$escGreen("zapm"))_" "_##class(%ZAPM.ext.zpm).GetModuleVersion("zapm",##class(%ZAPM.ext.zpm).#GNSET),!
		if $$EXIST^%R("%ZAPM.ed.a") write !,$$$escGreen("zapm-editor")_" "_##class(%ZAPM.ext.zpm).GetModuleVersion("zapm-editor",##class(%ZAPM.ext.zpm).#GNSET),!
		write !,$ZVersion,!
	}
	if $p(cmd," ")="info" quit ##class(%ZAPM.ext.zpm).info($p(cmd," ",2,*)_" ")
	if $p(cmd," ")="repo" set st=##class(%ZPM.PackageManager).Shell(cmd) do:cmd'="repo -list"&&(cmd["repo -r -n ") ##class(%ZPM.PackageManager).Shell("repo -list") quit st
	if $p(cmd," ")="upg" quit ##class(%ZAPM.ext.zpm).Upgrade($p(cmd," ",2,*))
	if $e(cmd,1,2)="ed" quit ##class(%ZAPM.ext.zpm).editor(cmd) 
	if $p(cmd," ")="dbcreate" {
		if ($p(cmd," ",2,*))[" -p " set path=$p($p(cmd," -p ",2)," ")
		 quit ##class(%ZAPM.ext.database).CreateDBNS($p(cmd," ",2),,$GET(path))
	}
	if $p(cmd," ")="dbdelete" write !,"Delete database,namespace "_$p(cmd," ",2,*)_": " quit ##class(%ZAPM.ext.database).DeleteDBNS($p(cmd," ",2,*))
	
	;if $p(cmd," ")="rolecreate" quit ##class(%ZAPM.ext.database).CreateRole($p(cmd," ",2,*))
	;if $p(cmd," ")="roledelete" quit ##class(%ZAPM.ext.database).DeleteRole($p(cmd," ",2,*))
}

/// write ##class(%ZAPM.ext.zpm).SetModuleVersion("zapm","^%ZAPM.settings","1.0.15")
ClassMethod SetModuleVersion(modulename = "zapm", gn = {..#GNSET}, ver = "") As %Status
{
	do ##class(%ZAPM.ext.zpm).GetListModule(,.List,0)
	set st=$$$OK
	if '$D(List(modulename,"L"),data) quit $$$ERROR($$$GeneralError,"there is no module '"_modulename_"' in the namespace '"_$namespace_"'")
	set root=$lg($g(data),3) 
	set desc=$lg($g(data),2) 
	if root="" quit $$$ERROR($$$GeneralError,"there is no root defined in the namespace '"_$namespace_"' for the module '"_modulename_"'")
	do ..GetFileLines(root_"module.xml",.out)
	set i="" for  {set i=$o(out(i),1,str) q:i=""  
		if str["<Version>" set ver=$p($p(str,"<Version>",2),"<") quit
	}
	if $G(ver)="" quit $$$ERROR($$$GeneralError,"no version number found in the module file")
	try {
		set @gn@("Modules",modulename,"Version")=ver
		if $G(List(modulename,"R"))'="" {
			set @gn@("Modules",modulename,"Remote")=$G(List(modulename,"R"))
			set repo=$lg(List(modulename,"R"),3)
			set:repo'="" @gn@("Modules",modulename,"Repository")=repo
		}
		set:$G(List(modulename,"L"))'="" @gn@("Modules",modulename,"Local")=$G(List(modulename,"L"))
		set:desc'="" @gn@("Modules",modulename,"Desc")=desc
		if 
	}
	catch e {
		set st=$$$ERROR($$$GeneralError,$ze)
		quit
	}
	quit st
}

/// write ##class(%ZAPM.ext.zpm).GetModuleVersion()
ClassMethod GetModuleVersion(modulename = "zapm", gn = {..#GNSET}) As %Status
{
	quit $GET(@gn@("Modules",modulename,"Version"),"0.0.?")
}

ClassMethod editor(cmd) As %Status
{
	if '$$EXIST^%R("%ZAPM.ed.a") write !,"Extension zapm-editor not installed. To install, run: zapm ""install zapm-editor"" " quit $$$OK
	if $e(cmd,1,5)="edit-" set cmd="ed"_$e(cmd,6)_" "_$p(cmd," ",2,*)
	if $p(cmd," ")="edt" do ^%ZAPM.ed.BSC,rest quit $$$OK
	if $p(cmd," ")="edz" do nszpm^%ZAPM.ed.a,rest quit $$$OK
	if $p(cmd," ")="edg" do glo^%ZAPM.ed.a($p(cmd," ",2)),rest quit $$$OK
	if $p(cmd," ")="edr" do rou^%ZAPM.ed.a($p(cmd," ",2)),rest quit $$$OK
	if $p(cmd," ")="edf" do FileSys^%ZAPM.ed.a($p(cmd," ",2)),rest quit $$$OK ;file system navigator
	if $p(cmd," ")="eds" if $$appinstall() do SQLTab^%ZAPM.ed.a($p(cmd," ",2)),rest quit $$$OK ;sql queries
	if $p(cmd," ")="edl" if $$appinstall() do SQLLockTab^%ZAPM.ed.a($p(cmd," ",2)),rest quit $$$OK ;sql queries
	if $p(cmd," ")="edj" if $$appinstall() do SQLJobs^%ZAPM.ed.a($p(cmd," ",2)),rest quit $$$OK ;sql queries
	quit $$$OK
rest open 0:(:) write $$$escClear
 quit
appinstall() 
 if '$$EXIST^%R("apptools.core.LogInfoPane.1") write !,"Modele ZPN ""apptools-admin"" not installed. To install, run: zapm ""install apptools-admin"" " quit 0
 quit 1
}

ClassMethod info(extcmd) As %Status
{
	set tDesc=1 ;+$g(pCommandInfo("data","Desc"))
	quit:'..GetListModule(,.tModMap,'tDesc)
		Set tMod = ""
		For { Set tMod = $Order(tModMap(tMod),1,tVersion)
			Quit:(tMod="")
			Write !,$$$escGreen(tMod)," ",tVersion_" "
			If tDesc,$Data(tModMap(tMod,"L"),Lock) {
				Set maxlenname=$L(tMod_" "_tVersion_" ")
				Do ..DrawColumn($$$escYellow("Description: ")_$ListGet(Lock,2))
				Set au=3 
				For a="Author_CopyrightDate", "Author_License", "Author_Notes", "Author_Organization", "Author_Person" { 
					Set au=au+1
					set audata=$ListGet(Lock,au)
					Write:audata'="" !
					,?(maxlenname)
					,..DrawColumn($$$escMagenta(a_": ")_audata)
				}
				set dirroot=$ListGet(Lock,3)
				Write !
					,?(maxlenname)
					,..DrawColumn($$$escMagenta("Root: ")_dirroot)
				if $Data(tModMap(tMod,"R"),Rem) {
					write !,$ListGet(Rem,3)
				}
				if (extcmd)["-r " kill out do ..GetFileLines(dirroot_"README.md",.out),..DrawArray(.out)
				if (extcmd)["-m " kill out do ..GetFileLines(dirroot_"module.xml",.out),..DrawArray(.out)
				if (extcmd)["-f " kill out do ..GetAllDir(dirroot,,.out),..DrawArray(.out,dirroot)
			}
		}
	quit $$$OK
}

ClassMethod DrawArray(ByRef Array As %String, ListDir = "") As %Status
{
	set i="" for  {set i=$o(Array(i),1,str) q:i=""  
		if ListDir="" write !,$$$escRed(str) continue
		if $lg(str,2)="F" write !,$$$escRed($p($lg(str,1),ListDir,2))
	}
}

/// Get all files in a directory and subdirectories
ClassMethod GetAllDir(dir, ext = "", ByRef out)
{
	set dir = ##class(%File).NormalizeDirectory(dir)
	set rs = ##class(%ResultSet).%New("%File:FileSet")
	s sc=rs.Execute(dir, ext)
	while (rs.Next()) {
		set out($i(out)) = $lb(rs.Get("Name"),rs.Get("Type"),rs.Get("Size"),rs.Get("ItemName"),rs.Get("DateCreated"),rs.Get("DateModified"))
		if rs.Get("Type")="D" d ..GetAllDir($lg(out(out),1),ext,.out)
	}
	q $$$OK
}

/// from %ZPM.PackageManager.Developer.Utils
ClassMethod GetFileLines(pFileName As %String, Output pOutput) As %Status
{
	Set tSC = $$$OK
	set curio=$i
	Try {
		Kill pOutput
		Close pFileName Open pFileName:("RS"):5
		If '$T Set tSC = $$$ERROR($$$CacheError, "Failed to open file '"_pFileName_"'") Quit
		Set TooMuch = 0
		Use pFileName
		For {
			// Keep reading through end of file; save only first 32,000 characters
			Set tLine = "" Read tLine:1
			If '$T && (tLine=$C(-1)) Quit  // Exit by timeout
			If $Length(tLine)<32000 {
				Set pOutput($i(pOutput)) = tLine
			} Else {
				Set pOutput($i(pOutput)) = $E(tLine,1,32000)_" (more...)"
			}
			If ($ZEOF=-1) Quit  // Exit by EOF
		}
		Close pFileName
	} Catch e {
		Set tSC = e.AsStatus()
		Close pFileName
	}
	use curio
	Quit tSC
}

ClassMethod find(extcmd) As %Status
{
	if (extcmd)[" -r " set ViewRepo=1
	if (extcmd)[" -d " set ViewFromModule=1
	if (extcmd)[" -u " set ViewUrl=$p($p(extcmd," -u ",2)," ")
	do ##class(%ZAPM.ext.zpm).Description($p(extcmd," "),$GET(ViewUrl),$GET(ViewRepo),$GET(ViewFromModule))
	quit $$$OK
}

ClassMethod help(cmd = "") As %Status
{
	OPEN 2:$j USE 2
	if '$lf(..cmdzpmext(),cmd) {
		do ##class(%ZPM.PackageManager).Shell("help "_cmd)
		do ##class(%ZAPM.ext.zpm).exthelp(cmd)
	}
	else { 
		do ##class(%ZAPM.ext.zpm).exthelp(cmd)
		}
 	CLOSE 2
 	set i=""
 		,help=""
 		,cmds=..cmdzpm()_..cmdzpmext()
 	for { set i=$o(^SPOOL($j,i),1,s) q:i=""
 		set s=" "_s
 		if $o(^SPOOL($j,i)) {
	 		for cm=1:1:$ll(cmds) if s[(" "_$lg(cmds,cm)_" ") set s=$replace(s," "_$lg(cmds,cm)_" "," "_$$$escMagenta($lg(cmds,cm))_" ")
 			set help=help_s
 		}
 	}
 	KILL ^SPOOL($j)
	write !,help
	quit $$$OK
}

ClassMethod exthelp(cmd = "") As %Status
{
 if cmd="" {
	write !!,"Available commands extention:"
	write !,"-----------------------------"
 }
 if cmd=""||(cmd="newdb") {
	write !!,"newdb <module>"
 	write !," Create a new database and an Namespace with a name derived from the name of the module and Install the module into it,"
 }
 if cmd=""||(cmd="dbcreate") {
	write !!,"dbcreate namespace <path>"
 	write !," Create a new database and an Namespace,"
 	write !," dbcreate testdb2 -p d:/!/database/durable"
 }
 if cmd=""||(cmd="dbdelete") {
	write !!,"dbdelete namespace"
 	write !," Delete database and an Namespace,"
 }
 if cmd=""||(cmd="info") {
	write !!,"info "
 	write !," Show more complete information about modules in the current namespace."
	write !,"info -m module"
 	write !," Show file module.xml."
	write !,"info -f module"
 	write !," List file in repository."
	write !,"info -r module"
 	write !," Show file readme.md."
 }
 if cmd=""||(cmd="upg") {
	write !!,"upg "
 	write !," Upgrade the versions of modules installed in the current namespace."
 }
 if cmd=""||(cmd="load") {
	write !!,"load http://git-repo/developer-name/repo-name"
 	write !," Load the module directly from the repository into the current Namespace. The 'git clone' command is applied. The git program must be installed."
 }
 if cmd=""||(cmd="find")||(cmd="search") {
	write !!,"find app* -d  load description from modules, and the description is always displayed"
 	write !!,"find app* -u /rcemper  show modules only including context from repository"
 }

 if cmd=""||(cmd="cmd") {
	write !!,"cmd "
 	write !,"  Alias: ?"
 	write !," Show all commands."
 	write !!,"cmd <context>"
 	write !," Show all commands including context."
 	write !!,"cmd -init"
 	write !," Reload all commands. Run do ##class(%ZAPM.ext.zapp).init()"
 }
 if cmd=""||(cmd="hist") {
	write !!,"hist "
	write !,"  Alias: ??"
 	write !," Show all history."
 	write !!,"hist <context>"
 	write !," Show all history including context."
 	write !!,"hist - <context>"
 	write !," Show all history including context. Sorting by date"
 	write !!,"hist + <context>"
 	write !," Show all history including context. Reverse sorting by date"
 	write !!,"hist -del Number_day"
 	write !," Delete all history older than the number of days."
 	write !!,"hist -add Number_hist"
 	write !," Added history in list for non-removable."
 	write !!,"hist -add Number_hist [name_cmd] [a/i/n] description"
 	write !," Added history in list commans."
 }
 if $$EXIST^%R("%ZAPM.ed.a") {
	if cmd=""||($e(cmd,1,2)="ed") {
	write !!,"edit-glo - Globals and lockals editor"
	write !,"  Alias: edg "
	write !,"    edg ^globaltest"
	write !,"    edg localarray"
	write !,"edit-rou - Routine editor"
	write !,"  Alias: edr "
	write !,"    edr ^rouname"
	write !,"edit-zpm - Navigator for zpm"
	write !,"  Alias: edz "
	write !,"edit-file - Filesystem navigator"
	write !,"  Alias: edf "
	write !,"    edf /home/file.txt"
	write !,"    edf mess - view file messages.log"
	write !,"    edf cpf - view file iris.cpf"
	write !,"edit-lock - Locktab navigator"
	write !,"  Alias: edl "
	write !,"edit-job - Job navigator"
	write !,"  Alias: edj "
	write !,"edit-sql - SQL query executor"
	write !,"  Alias: eds "
	write !,"    eds select * from sample.person"
	}
}
 write !
	quit $$$OK
}

ClassMethod cmdzpm() As %String
{
	quit $lb("ver","quit","help","namespace","orphans","list-dependents","list-installed","reload","compile","test","package","verify","publish","load","zn","help","install","uninstall","manage","list","find","search","version","repo","config","generate")
}

ClassMethod cmdzpmext() As %String
{
	quit $lb("newdb","cmd","hist","dbcreate","dbdelete","upg","info","edit-tab","edt","edit-glo","edg","edit-lock","edl","edj","edit-job","edr","edit-rou","edz","edit-zpm","edf","edit-file","eds","edit-sql")
}

/// do ##class(%ZAPM.ext.zpm).SetColorScheme("dark")
ClassMethod SetColorScheme(scheme = {$s($zversion(1)=3:"dark",1:"white")}) As %Status
{
	write !,1,scheme,1
	Quit ##class(%ZPM.PackageManager).Shell("config set ColorScheme "_scheme)
}

/// Upgrade all installed modules
/// write ##class(%ZAPM.ext.zpm).Upgrade()
ClassMethod Upgrade(ns = {$namespace}) As %Status
{
	do ##class(%ZAPM.ext.zpm).GetListModule(ns,.List,0)
	set name=""
	for { set name=$Order(List(name)) quit:name=""
		if $g(List(name,"R"))'="",$LISTGET(List(name,"L"),1)'=$LISTGET(List(name,"R"),1) {
			set Diff(name)="" 
			write !," "_$$$escGreen(name)_" Local: "_$LISTGET(List(name,"L"),1)_" Registr: "_$LISTGET(List(name,"R"),1)
		}
	}
	if '$DATA(Diff) {
		write !,"The versions of the modules are the same. Updating anyway? [Y/N]<N>"
		read upd
		if $zconvert(upd,"L")["y" do ..UpgradeList(.List)
	}
	else {
		write !,"Updating different modules or all? [Y/A/N]<N>"
		read upd 
		set upd=$zconvert(upd,"L")
		if upd["y" {do ..UpgradeList(.Diff)}
		elseif upd["a" {do ..UpgradeList(.List)}
	}
	quit $$$OK
}

/// write ##class(%ZAPM.ext.zpm).UpgradeList(.list)
ClassMethod UpgradeList(List) As %Status
{
	set name=""
	for { set name=$Order(List(name)) quit:name=""
		zpm "install "_name
	}
}

/// do ##class(%ZAPM.ext.zpm).GetListModule(,.List)
/// Get module list in currently namespace
ClassMethod GetListModule(ns = {$namespace}, ByRef Mod, OnlyName = 1) As %Status
{
	new $namespace
	set $namespace=ns
	Set tRes = ##class(%SQL.Statement).%ExecDirect(,
		"select * from %ZPM_PackageManager_Developer.""MODULE""")
	If (tRes.%SQLCODE < 0) {
		Throw ##class(%Exception.SQL).CreateFromSQLCODE(tRes.%SQLCODE,tRes.%Message)
	}
	set in=""
	While tRes.%Next(.tSC) {
		$$$ThrowOnError(tSC)
		Set name=tRes.%Get("Name")
		set in=in_"'"_name_"',"
		set list=$lb(tRes.%Get("VersionString"),tRes.%Get("Description"),tRes.%Get("Root"))
		For a="Author_CopyrightDate", "Author_License", "Author_Notes", "Author_Organization", "Author_Person" {
			Set list=list_$lb(tRes.%Get(a))
		}
		Set Mod(name) = tRes.%Get("VersionString")
		Set:'OnlyName Mod(name,"L") = list
		
	}
	$$$ThrowOnError(tSC)
	quit:in=""||(OnlyName) $$$OK
	set in=$Extract(in,1,*-1)
	do ##class(%ZAPM.ext.zpm).GetVerZpm(.IsHspm,.RepoFieldName)
	Set tQuery = "select Name, Version, "_RepoFieldName_", Description from %ZPM_PackageManager_Developer.Utils_GetModuleList('registry') WHERE name in ("_in_")"
	Set tRes = ##class(%SQL.Statement).%ExecDirect(,tQuery)
	
	If (tRes.%SQLCODE < 0) {
		Throw ##class(%Exception.SQL).CreateFromSQLCODE(tRes.%SQLCODE,tRes.%Message)
	}
	While tRes.%Next(.tSC) {
		$$$ThrowOnError(tSC)
		Set Mod(tRes.%Get("Name"),"R")=$Listbuild(tRes.%Get("Version"),tRes.%Get("Description"),tRes.%Get(RepoFieldName))
	}
	quit $$$OK
}

/// write ##class(%ZAPM.ext.zpm).LoadFromRepo("https://github.com/Vassil2010/iris-sms")
ClassMethod LoadFromRepo(path = "") As %Status
{
	set sls=$$$slash
	set st=$$$OK
	if $e(path,1,4)="http" {
		set dirrepo=$p($p(path,"/",*),".git")
		set dirrnd=$tr($zts,".,")
		Set TempDir = ##class(%File).GetDirectory(##class(%File).GetDirectory($zu(86))_"mgr"_sls_"Temp"_sls_dirrnd_sls)
		set st=##class(%File).CreateDirectoryChain(TempDir)
		if 'st  write !,$System.Status.GetErrorText(st) q st
		;write !,"Create tempory directory "_TempDir
		//first try
		set UrlArchive = ..GetUrlRepoArhive(path)
		if UrlArchive'="" {
			Do ##class(%Net.URLParser).Parse(UrlArchive,.tComponents)
			Set tClient = ##class(%ZPM.PackageManager.Client.REST.PackageManagerClient).%New()
			set tRequest = tClient.GetHttpRequest(UrlArchive)
			Set tRequest.Timeout = 300
    		Set tSC = tRequest.Get(tComponents("path"))
    		If $$$ISOK(tSC), tRequest.HttpResponse.StatusCode=200 {
      			Set tFileBinStream = ##class(%Stream.FileBinary).%New()
      			Set tFileBinStream.Filename = TempDir_"tmp.zip"
      			do tFileBinStream.CopyFromAndSave(tRequest.HttpResponse.Data)      
			}
		  	If $GET(tFileBinStream)'="" {
				if $zversion(1)=3 { //for Linux
					set cmd="cd "_TempDir_" && unzip -q tmp.zip"
				}
				else { //for Windows
					set cmd="cd "_TempDir_" && powershell Expand-Archive -LiteralPath "_TempDir_"tmp.zip -DestinationPath "_TempDir
				}
				write !,cmd,!
				$$$ThrowOnError(##class(%ZPM.PackageManager.Developer.Utils).RunCommandViaZF(cmd,.tLog,.tErr))
				hang 2
			}
		}
		if $$$FileSize(TempDir_dirrepo_"-master"_sls_"module.xml")>0 {
			set st=##class(%ZPM.PackageManager).Shell("load "_TempDir_sls_dirrepo_"-master")
			do ##class(%File).RemoveDirectoryTree(TempDir)
			if 'st write !,$System.Status.GetErrorText(st)
			Quit st
		}
		//second try
		set cmd="cd "_TempDir_" && git clone "_path
		write !,cmd,!
		$$$ThrowOnError(##class(%ZPM.PackageManager.Developer.Utils).RunCommandViaZF(cmd,.tLog,.tErr))
		hang 2
		if $$$FileSize(TempDir_dirrepo_sls_"module.xml")>0 {
			set st=##class(%ZPM.PackageManager).Shell("load "_TempDir_sls_dirrepo)
			do ##class(%File).RemoveDirectoryTree(TempDir)
			if 'st write !,$System.Status.GetErrorText(st)
			Quit st
		}
	}
	else {
		Quit ##class(%ZPM.PackageManager).Shell("load "_path)
	}
	q $$$OK
}

/// https://github.com/SergeyMi37/zapm-addcmd.git
/// https://codeload.github.com/SergeyMi37/zapm/zip/master
/// write ##class(%ZAPM.ext.zpm).GetUrlRepoArhive("https://github.com/SergeyMi37/zapm-addcmd.git")
/// https://gitlab.com/sergeymi/test.git
/// https://gitlab.com/sergeymi/test/-/archive/master/test-master.zip
/// write ##class(%ZAPM.ext.zpm).GetUrlRepoArhive("https://gitlab.com/sergeymi/test.git")
ClassMethod GetUrlRepoArhive(tLocation) As %String
{
	Do ##class(%Net.URLParser).Parse(tLocation,.tComponents)
	set reponame=$piece($piece(tComponents("path"),"/",3),".")
	If tComponents("host")="gitlab.com" {
		set ref="https://gitlab.com/"_$piece(tComponents("path"),"/",2)_"/"_reponame_"/-/archive/master/"_reponame_"-master.zip"
	}
	If tComponents("host")="github.com" {
		set ref="https://codeload.github.com/"_$piece(tComponents("path"),"/",2)_"/"_reponame_"/zip/master"
	}
	quit $get(ref)
}

/// d ##class(%ZAPM.ext.zpm).UnloadAndDeleteDBNS("sync-dstime")
ClassMethod UnloadAndDeleteDBNS(name, Version = "", Repo = "", gn = {..#GN}) As %Status
{
	set currns=$namespace
	new $namespace
	s ns=$zconvert($tr(name,"-."),"U")
	set $Namespace=ns
	set sta=##class(%ZPM.PackageManager).Shell("uninstall "_name)
	if 'sta w !,$system.Status.GetErrorText(sta)
	else  k @gn@(name)
	set $namespace=currns
	s st=##class(%ZAPM.ext.database).DeleteDBNS(ns)
	i 'st w $system.Status.GetErrorText(st)
}

/// d ##class(%ZAPM.ext.zpm).CreateDBNSAndLoad("isc-tar")
ClassMethod CreateDBNSAndLoad(name, ns = "", Version = "", Repo = "", gn = "", err) As %Status
{
	new $namespace
	k err w !
	if ns="" s ns=$zconvert($tr(name,"_$.","-S"),"U")
	s st=##class(%ZAPM.ext.database).CreateDBNS(ns)
	i 'st s err=$System.Status.GetErrorText(st) w !,err
	s:gn'="" @gn@(name,"generate")=$lb(ns,$g(err),st)
	if st {
		;s sta=$zpm("install "_name_" -v")
		kill err
		do ..InstallModule(name, ns, Version, Repo, gn, .err)
		if $g(err)["<INTERRUPT>" quit sta
	}
	q $$$OK
}

ClassMethod InstallModule(name, ns = "", Version = "", Repo = "", gn = "", err) As %Status
{
	new $namespace
	zn ns
	;s sta=$zpm("install "_name_" -v")
	kill err
	write !,"zpm ""install "_name_""""
	set sta=##class(%ZPM.PackageManager).Shell("install "_name)
	if 'sta s err=$System.Status.GetErrorText(sta) w !,err 
	if gn'="" {
		set @gn@(name,"install")=$lb($g(err),sta,Version,Repo,+$h,ns)
		set @gn@(name,"url")="<a target='_new' href='"_Repo_"'>"_Repo_"</a>"
	}
	quit sta
}

/// Recompilation to IRIS namespace
/// d ##class(%ZAPM.ext.zpm).CompNS("AAA")
ClassMethod CompNS(ns) As %Status
{
	zn ns
	d ##class(%EnsembleMgr).EnableNamespace(ns,1)
	w !,"Compilation started, please wait..."
	k err d $system.OBJ.CompileAll("cfk-u-d",.err) zw err
	q $$$OK
}

ClassMethod CollectPackage(pPath As %String, Output pList, pRoot As %String)
{
  set rs = ##class(%File).FileSetFunc(pPath)
  WHILE rs.%Next() {
    If rs.Type="D" {
      do ..CollectPackage(rs.Name, .pList, pRoot)
    } ELSE {
      #; Set $LISTBUILD(url) = $SYSTEM.CSP.FilenameToUrls(rs.Name) 
      Set pList($INCREMENT(pList)) = $LISTBUILD(rs.Name, $EXTRACT(rs.Name, $LENGTH(pRoot) + 1, *))
    }
  }
}

ClassMethod CompactPackage(ByRef pList, classname = {$CLASSNAME()}) As %Status
{
  set file = ""
  for i=1:1:$Get(pList) {
    Set $LISTBUILD(file, name) = pList(i)
    
    set tmpFile = ##class(%File).TempFilename("gz")

    set stream = ##class(%Stream.FileBinary).%New()
    set stream.Filename = file

    Set gzip = ##class(%Stream.FileBinaryGzip).%New()
    Set gzip.Filename = tmpFile
    do gzip.CopyFromAndSave(stream)
    
    Set gzip = ##class(%Stream.FileBinary).%New()
    Set gzip.Filename = tmpFile

    Set xdata = ##class(%Dictionary.XDataDefinition).%New()
    Set xdata.Name = "Data"_i
    Set xdata.Description = name
    Do xdata.parentSetObjectId(classname)
    set chunkSize = 22800
    while 'gzip.AtEnd {
      set data = gzip.Read(chunkSize)
      set base64 = $SYSTEM.Encryption.Base64Encode(data)
      do xdata.Data.WriteLine(base64)
      set data1 = $SYSTEM.Encryption.Base64Decode(base64)
    }
    do xdata.%Save()
    set hash = $SYSTEM.Encryption.SHA1HashStream(gzip)
  
    do ##class(%File).Delete(tmpFile)
  }
  QUIT $$$OK
  
  
  Quit $$$OK
}

ClassMethod ExtractPackage(Output pFolder As %String, classname = {$CLASSNAME()}) As %String
{
  Set pFolder = ##class(%File).NormalizeDirectory($$$FileTempDir)

  For i=1:1:..#FILESCOUNT {
    Set xdata = ##class(%Dictionary.XDataDefinition).%OpenId(classname_"||Data"_i)
    Set name = xdata.Description
    Set fileName = pFolder_name

    Set tParentFolder = ##class(%File).ParentDirectoryName(fileName)    
    if '##class(%File).DirectoryExists(tParentFolder) {
      Do ##class(%File).CreateDirectoryChain(tParentFolder)
    }

    set tmpFile = ##class(%File).TempFilename("gz")

    set stream = ##class(%Stream.FileBinary).%New()
    set stream.Filename = tmpFile
    set prev = ""
    set chunkSize = 30400
    do {
      set data = prev
      if 'xdata.Data.AtEnd {
        set data = data _ xdata.Data.Read()
      }
      set data = $ZSTRIP(data, "*C")
      set prev = $EXTRACT(data, chunkSize + 1, *)
      set data = $EXTRACT(data, 1, chunkSize)
      set chunk = $SYSTEM.Encryption.Base64Decode(data)
      do stream.Write(chunk)
    } while (prev'="")||('xdata.Data.AtEnd)
    do stream.%Save()

    set gzip = ##class(%Stream.FileBinaryGzip).%New()
    set gzip.Filename = tmpFile

    set fs = ##class(%Stream.FileCharacter).%New()
    set fs.Filename = fileName
    do fs.CopyFromAndSave(gzip)

    do ##class(%File).Delete(tmpFile)
  }
  Quit $$$OK
}

/// Add XDATA to another class
///  d ##class(%ZAPM.ext.zpm).add2xdata("/backup/iris/distr/apptools-task/","Test.test")
ClassMethod add2xdata(dir = "d:\_proj\_zpm\appt-core\src\cls\", classname)
{
	;w $classname() q
	Do ..CollectPackage(dir, .tList, dir)
	zw tList
    ;Do ##class(%ZPM.Installer).CompactPackage(.tList,"App.MSW.type")
    Do ..CompactPackage(.tList,classname)
}

/// Output color escape sequence
/// do ##class(%ZAPM.ext.zpm).EscColor()
ClassMethod EscColor(mode = "") As %String
{
	if mode="" { //write all colors
		write ..EscColor(0)
		//brightness
		for b=1,2 {
			for f=30:1:37 {  //font
				for i=40:1:47 {  //background
					s code=b_";"_f_";"_i
					s txt=" write $$$escSeq("""_code_""",""any text"")"
					w !,$$$escSeq(code,txt)
				}
			}
		}
	
	} elseif mode=0 { //cleaning
		q $c(27)_"[0m"
	} else {
		q $c(27)_"["_mode_"m"
	}
}

/// write ##class(%ZAPM.ext.zpm).ZPMColorScheme()
ClassMethod ZPMColorScheme() As %String
{
	try {
		set scheme=##class(%ZPM.PackageManager.Client.Settings).GetValue("ColorScheme")
	} 
	catch e {
		set scheme=0
	}
	quit scheme
}

/// Version ZPM 
/// write ##class(%ZAPM.ext.zpm).GetVerZpm(.IsHspm)
ClassMethod GetVerZpm(ByRef IsHspm, ByRef RepoFieldName)
{
	new $namespace
	set $namespace="%SYS"
	Do ##class(%ZPM.PackageManager).GetListModules("zpm",.list)
	If $Data(list("zpm")) {
			set ver=$ListGet(list("zpm"),1)
	}
	set IsHspm=0
	if $p(ver,".",2)=2,$p(ver,".",3)>14 set IsHspm=1
	if $p(ver,".",2)>2 set IsHspm=1
	set RepoFieldName="Repo" 
	if IsHspm set RepoFieldName="Repository" 
	Quit $Get(ver)
}

/// Show description 
/// do ##class(%ZAPM.ext.zpm).Description("z*","/rcep",1)
ClassMethod Description(tModuleName, UrlInc = "", RepoView = "0", ViewFromModule = 0)
{
	#define gn "^||tmpDesc"
	Kill @$$$gn
	Set tRegistry = ""
	If (tModuleName["/") {
		set $lb(tRegistry, tModuleName) = $lfs(tModuleName, "/")
	}
	set where=""
		,maxlenname=0
		,Module=""
	If tModuleName["*" {
		Set where="where name like ?"
		Set Module=$Replace(tModuleName,"*","%")
	} Elseif tModuleName'="" { 
		Set Module=tModuleName
		Set where="where name = ?"
	}
	do ##class(%ZAPM.ext.zpm).GetVerZpm(.IsHspm,.RepoFieldName)
	If UrlInc'="" set RepoView=1 Write !,"Search by owner repository "_$$$escRed(UrlInc) Set where=where_" order by "_RepoFieldName_" "
	If where="" Write !,"Search the entire repository"
	Else  Write !,"Search the repository context "_Module
	
	//Load the list info registry modules
	Set sql="select Name, Version, "_RepoFieldName_", Description from %ZPM_PackageManager_Developer.Utils_GetModuleList('registry') "_where
		,rs=##class(%ResultSet).%New()
		,sc=rs.Prepare(sql)
	Set:sc sc=rs.Execute(Module)
	set maxlenname=20
	If sc {
		For i=1:1 {
			Quit:'rs.%Next()  
			Set name=rs.Get("Name")
			set (Description,desc)=rs.Get("Description")
			Set (repo,url)=rs.Get(RepoFieldName)
			If $Zconvert(url,"L")'[$Zconvert($Get(UrlInc),"L") Continue
			if desc="",ViewFromModule	{
				Do ..GetDescFromRepo(url,.desc,.repo,.modxml)
				if desc="" { set desc="not yet"}
				else { set desc="from module.xml: "_desc}
			}
			Write !,$$$escGreen(name)
				,?(maxlenname+1),rs.Get("Version")
				,?(maxlenname+8),$$$escYellow("Desc: ")_desc
			if $Get(UrlInc)'="",repo'="" set repo=$replace(repo,UrlInc,$$$escRed(UrlInc))
			if RepoView write:repo'="" !?3,repo
		 }
	}
	Else { 
		Write !,"Not found "_tModuleName_" in current registry"
	}
	Quit $$$OK
}

/// draw description, code from zpmshow.mac
ClassMethod DrawColumn(desc) As %String
{
 Set dx=$x
	For d=1:1:$Length(desc," ") {
 		Set wd=$Piece(desc," ",d) 
		If $x+$l(wd)>80 Write !,?dx
		Write wd," " 
	}
 Quit ""
}

/// TODO GitLab repo
ClassMethod GetDescFromRepo(url As %String, ByRef desc, ByRef repo, ByRef modxml) As %Status
{
	Set desc=""
	Set url="https://raw.githubusercontent.com"_$Piece(url,"/github.com",2)
	If url="" {
		Set repo="not repository"
	}
	Else {
		Set:$Extract(url,*)'="/" url=url_"/"
		Set url=url_"master/module.xml"
		If ..GetDataURL(url,.modxml) {
			Set desc=$Piece($Piece($Get(modxml),"Description>",2),"</")
			If 0,desc="",..GetDataURL($replace(url,"module.xml","README.md"),.readme) {
				Set d=$Translate($Extract(readme,1,300),$Char(13,10),"  ")
				If d["](" {
					For  { Quit:d'["]("
						Set d=$Translate($Piece(d,"](",1),"[()","   ")_$Piece($Piece(d,"](",2,*),")",$Select($Piece(d,"](",2,*)[")":2,1:1),*)
						
					}
				}
				Set desc="from readme: "_d_"..."
			}
		}
	}
	Quit $$$OK
}

ClassMethod SetProxy(ByRef req) As %Status
{
	set proxy=$System.Util.GetEnviron("https_proxy")
	if proxy'="" {
		Do ##class(%Net.URLParser).Parse(proxy,.pr)
		if (req.Https) {
			set req.ProxyHTTPS=1
			set req.ProxyTunnel=1
		}
		set req.ProxyPort=pr("port")
		set req.ProxyServer=pr("host")
		if pr("username")'="",pr("password")'="" {
			set req.ProxyAuthorization="Basic "_$system.Encryption.Base64Encode(pr("username")_":"_pr("password"))
		}
	}
 quit $$$OK
}

/// write $System.Status.GetErrorText(##class(%ZAPM.ext.zpm).GetDataURL("https://raw.githubusercontent.com/intersystems-community/zpm/master/module.xml",.o)) w o
ClassMethod GetDataURL(url As %String, ByRef data, ByRef req) As %Status
{
	New $Namespace
	Set data=""
 	;#dim req As %Net.HttpRequest
	Set req=##class(%Net.HttpRequest).%New()
	Set server=$p(url,"/",3)

	If server[":" {
		Set port=$p(server,":",2)
		Set server=$p(server,":")
	}
	If $zconvert(url,"L")["https:" {
	 	Set SSLConfig = "ZPM"
	 	Zn "%SYS"
	 	Do:'##class(Security.SSLConfigs).Exists(SSLConfig) ##class(Security.SSLConfigs).Create(SSLConfig)
	 	Set req.Https=1
		Set req.SSLConfiguration=SSLConfig
		Set:$g(port)="" port=443
	}
	do ..SetProxy(.req)

	Set:$Get(port)="" port=80
	Set req.Server=server
	Set req.Port=port
	Set location=$Piece(url,"/",4,*)

	Set req.Location =location

	Set st = req.Get()
	Return:$$$ISERR(st) st
	Return:(req.HttpResponse.StatusCode = 404) $$$ERROR($$$GeneralError,"Repository doesn't exist OR you don't have access")
	Return:((req.HttpResponse.StatusCode = 403) && (req.HttpResponse.GetHeader("X-RATELIMIT-REMAINING")=0)) $$$ERROR($$$GeneralError,"API rate limit exceeded. Try logging in.")
 	Return:(req.HttpResponse.StatusCode '= 200) $$$ERROR($$$GeneralError,"Received " _ req.HttpResponse.StatusCode _ " status, expected 200")

	Set data=req.HttpResponse.Data.Read()

 	Return $$$OK
}

}