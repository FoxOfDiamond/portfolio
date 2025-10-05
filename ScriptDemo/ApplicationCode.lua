----------------------------------------------------------------------Constants----------------------------------------------------------------------
tweenservice=game.TweenService
bodyheight=7
bodypos=Vector3.new(40,bodyheight,0)
mousepos=Vector3.new(40,bodyheight,0)
look=Vector3.new(1,0,0)
resting=true
segments={}
feet={}
base={}
rodir={50,-50,140,-140}
adjacent={{2,3},{1,4},{1,4},{2,3}}
tweenlist={}
tweenedlist={}

restingDistance=12
triggerDistance=10
iterations=15
speed=1
size=1
killable=true
--Length: 380 lines without comments

----------------------------------------------------------------------Weirdly specific function that offsets an origin by a pitch, with the yaw decided----------------------------------------------------------------------
----------------------------------------------------------------------by the vector mag. Only used for rotating the leg segments up and down while maintaining their length and yaw----------------------------------------------------------------------
function angleFromY(xz:Vector3,origin:Vector3,mag:Vector3,angle:number)
	local h=mag*math.cos(math.rad(angle))
	local w=mag*math.sin(math.rad(angle))
	return origin+Vector3.new(0,h,0)+xz*w
end
---------------------------------------------------------------------Rotates a vector by a direction, around the Y axis----------------------------------------------------------------------
function rotateVector(vec,dir)
	dir=math.rad(dir)
	return Vector3.new(vec.X*math.cos(dir)-vec.Z*math.sin(dir),0,vec.X*math.sin(dir)+vec.Z*math.cos(dir))
end
---------------------------------------------------------------------A quickly thrown together horror game mode where one player controls the spider to chase others----------------------------------------------------------------------
----------------------------------------------------------------------along with a command to trigger a speed boost and play a jumpscare, and a few others for debugging and messing around(size, speed, resetting, toggle killing players)----------------------------------------------------------------------
game.Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(char)
		local hum=char:FindFirstChildOfClass("Humanoid")
		hum.NameDisplayDistance=0
	end)
end)
game.TextChatService.Kill.Triggered:Connect(function(src,str)
	killable=not killable
end)
game.TextChatService.Speed.Triggered:Connect(function(src,str)
	speed=tonumber(string.split(str," ")[2])
	print(speed)
end)
game.TextChatService.Size.Triggered:Connect(function(src,str)
	size=tonumber(string.split(str," ")[2])
	print(size)
end)
game.TextChatService.Horror.Triggered:Connect(function(src,str)
	game.ReplicatedStorage.RemoteEvents.begin:FireAllClients(src.UserId)
end)
game.TextChatService.Cancel.Triggered:Connect(function(src,str)
	game.ReplicatedStorage.RemoteEvents.begin:FireAllClients(nil)
end)
game.TextChatService.Reset.Triggered:Connect(function(src,str)
	bodypos=Vector3.new(40,bodyheight,0)
	mousepos=Vector3.new(40,bodyheight,0)
end)
game.TextChatService.Dash.Triggered:Connect(function(src,str)
	workspace.sfx.jumpscare:Play()
	speed=3
	wait(5)
	speed=1
end)
---A segment, im not explaing every single properties, most are self explanatory. "Parent" is the previous segment in the chain (closer to the body), and "Child" is the next one in the chain
---n1 and n0 are the node joints, with n0 connected to the Parent and n1 connected to the Child
--Along with some functions 
type segment={
	n0:Vector3,
	n1:Vector3,
	Target:Vector3,
	Size:number,
	Parent:segment,
	Child:segment,
	Pull:(self,pos:Vector3,timeout:number)->nil,
	PullBack:(self,pos:Vector3,timeout:number)->nil,
	Straighten:(self,dir:Vector3)->nil,
	Display:(self)->nil,
--For display purposes
	part0:BasePart,
	part1:BasePart,
	footstep:Sound,
	visualizer:BasePart,
	beam:Beam,

	lerpTarget:Vector3,
	orDiff:number,
	grounded:boolean,
	legNum:number,
	feetHeight:number,
	resetQueue:boolean
}
--Constructor, self explanatory
local function newSegment(n0:Vector3,n1:Vector3,Size:number,Parent:segment,Child:segment):segment
	local new:segment={}
	new.Target=Vector3.new()
	new.lerpTarget=Vector3.new(0,100,0)
	new.orDiff=0
	new.grounded=true
	new.resetQueue=false
	
	new.n0=n0
	new.n1=n1
	new.Size=Size
	new.Parent=Parent
	new.Child=Child
	new.feetHeight=0
	--More setting up display things
	new.part0=Instance.new("Part")
	new.part0.CFrame=CFrame.new()
	new.part0.Size=Vector3.new(1,1,1)
	new.part0.Anchored=true
	new.part0.CanCollide=false
	new.part0.CanQuery=false
	new.part0.Name="SegmentDisplay"
	new.part0.Shape=Enum.PartType.Ball
	new.part0.Color=Color3.new(1,0,0)
	new.part0.Material=Enum.Material.Neon
	local att=Instance.new("Attachment")
	att.Parent=new.part0
	new.part0.Parent=workspace
	
	new.footstep=workspace.sfx.footstep:Clone()
	new.footstep.Parent=new.part0	
	
	new.part1=new.part0:Clone()
	new.part1.Name="part1"
	new.part1.Parent=new.part0
	
	new.visualizer=new.part0:Clone()
	new.visualizer.Shape=Enum.PartType.Cylinder
	new.visualizer.Size=Vector3.new(0.01,restingDistance*size,restingDistance*size)
	new.visualizer.Color=Color3.new(0,1,0)
	new.visualizer.CFrame=CFrame.new(0,-1,0)*CFrame.fromOrientation(0,0,math.rad(90))
	new.visualizer.Name="visualizer"
	new.visualizer.Parent=new.part0
	
	new.beam=Instance.new("Beam")
	new.beam.Attachment0=new.part0.Attachment
	new.beam.Attachment1=new.part1.Attachment
	new.beam.FaceCamera=true
	new.beam.Parent=new.part0
	
	function new:Reset():nil
		local restpos=Vector3.new(bodypos.X,0,bodypos.Z)+rotateVector(look,rodir[self.legNum]).Unit*restingDistance*size
		local restray=workspace:Raycast(restpos+Vector3.new(0,10,0),Vector3.new(0,-1,0)*100)
		if not restray then
			restray = {
				Position = Vector3.new(restpos.X,0,restpos.Z)
			}
		end
		self.lerpTarget=restray.Position
		tweenlist[self.legNum]=self.lerpTarget
		self.orDiff=(self.Target-self.lerpTarget).Magnitude
	end
	
    --Iterate stepping. The animation follows the upper half of a sine wave
	function new:Ground(i:number,cast:boolean):nil
		if tweenlist[self.legNum]=="done" then
			if not self.grounded then
				self.footstep.Volume=size
				self.footstep.PlaybackSpeed=math.max(0.95/math.sqrt(math.sqrt(math.sqrt(math.sqrt(math.sqrt(size))))),0.3)
				self.footstep:Play()
			end
			self.grounded=true
		else
			self.grounded=false
		end
		if cast then
			local ray=workspace:Raycast(self.lerpTarget+Vector3.new(0,400,0),Vector3.new(0,-1,0)*1000)
			local steppable=true
			
			for _,v in adjacent[i] do
				if not feet[v].grounded then
					steppable=false
				end
			end
			
			if ray and steppable and self.grounded then
				local restpos=Vector3.new(bodypos.X,0,bodypos.Z)+rotateVector(look,rodir[self.legNum]).Unit*restingDistance*size
				local restray=workspace:Raycast(restpos+Vector3.new(0,400,0),Vector3.new(0,-1,0)*1000)
				--self.visualizer.CFrame=CFrame.new(restray.Position)*CFrame.fromOrientation(0,0,math.rad(90))
				
				if restray then
					if self.resetQueue then
						print("Reset")
						self.resetQueue=false
						self.feetHeight=restray.Position.Y
						self.lerpTarget=restray.Position
						tweenlist[self.legNum]=self.lerpTarget
						self.orDiff=(self.Target-self.lerpTarget).Magnitude
						self.grounded=false
					elseif (ray.Position-restray.Position).Magnitude>triggerDistance*size then
						print("Step")
						self.feetHeight=restray.Position.Y
						self.lerpTarget=restray.Position
						tweenlist[self.legNum]=self.lerpTarget
						self.orDiff=(self.Target-self.lerpTarget).Magnitude
						self.grounded=false
					end
				end
			end
		end
		local h=math.sin(math.clamp((self.Target-self.lerpTarget).Magnitude/math.max(self.orDiff,1),0,1)*1.57*2)*4*size+self.feetHeight
		self:Pull(Vector3.new(self.Target.X,h,self.Target.Z),0)
	end
    --The IK itself. Standard recursive algorithm that iterates up and down the chain to ensure all segments are at the correct length
    --Pulls the joint connected to the child(n1) to the correct distance from n0
	function new:Pull(pos:Vector3,timeout:number): nil
		if timeout>iterations then
			return
		end
		
		self.n0=pos
		local off=(self.n1-self.n0).Unit*self.Size*size
		self.n1=self.n0+off
		
		if not self.Child then
			self.Target=pos
			if self.Parent then
				self.Parent:Pull(self.n1,timeout)
			end
		elseif self.Parent then
			self.Parent:Pull(self.n1,timeout)
		else
			self:PullBack(self.Target,timeout+1)
		end
		
	end
	
    --Pulls the joint connected to the parent(n0) back
	function new:PullBack(pos:Vector3,timeout:number): nil
		if timeout>iterations then
			return
		end
		
		self.n1=pos
		local off=(self.n0-self.n1).Unit*self.Size*size
		self.n0=self.n1+off
		
		if self.Child then
			if not self.Parent then
				local yAxis=Vector3.new(0,1,0)
				local vec=self.n0-self.n1
				local angle=math.deg(math.acos(vec:Dot(yAxis)/(vec.Magnitude)))
				self.n0=angleFromY(Vector3.new(vec.X,0,vec.Z).Unit,self.n1,self.Size*size,math.min(70,angle))
			end
			self.Child:PullBack(self.n0,timeout)
		else
			self:Pull(self.Target,timeout+1)
		end
	end
	
    --Make the entire chain points in a direction, required before recursive ik to make sure the limbs don't bend weird and are always upright
	function new:Straighten(dir:Vector3): nil
		if not self.Parent then
			dir=dir.Unit
			dir=Vector3.new(dir.X,1,dir.Z).Unit
			self.n1=self.Target
		else
			self.n1=self.Parent.n0
		end
		self.n0=self.n1+dir*self.Size*size
		if self.Child then
			self.Child:Straighten(dir)
		end
	end
	
    --Sets up the display parts
	function new:Display(): nil
		if not self.Parent then
			self.part0.Size=Vector3.new(2,2,2)*size
		else
			self.part0.Size=Vector3.new(1,1,1)*size
		end
		self.part1.Size=Vector3.new(1,1,1)*size
		self.beam.Width0=size
		self.beam.Width1=size
		if self.n0==self.n0 then
			self.part0.CFrame=CFrame.new(self.n0)
		end
		if self.n1==self.n1 then
			self.part1.CFrame=CFrame.new(self.n1)
		end
	end
	return new
end

--Spawns the limbs. This example uses 4 limbs with 3 segments each
for i=1,4 do
	local bs=newSegment(Vector3.new(4,15,0),Vector3.new(6,20,0),8)
	local mid=newSegment(Vector3.new(2,10,0),Vector3.new(4,15,0),9,nil,bs)
	local bod=newSegment(Vector3.new(0,5,0),Vector3.new(2,10,0),10,nil,mid)
	mid.Parent=bod
	bs.Parent=mid
	bod.Target=Vector3.new(0,4,0)
	bs.lerpTarget=Vector3.new(4,0,0)
	
	bs.legNum=i
	bod.legNum=i
	mid.legNum=i
	local colors={Color3.new(1,0,0),Color3.new(0,1,0),Color3.new(0,0,1),Color3.new(1,1,1)}
	bod.part0.Color=colors[i]
	bod.part0.Size=Vector3.new(2,2,2)
	
	bs:Reset()
	
	table.insert(segments,bs)
	table.insert(segments,mid)
	table.insert(segments,bod)

	table.insert(base,bod)
	table.insert(feet,bs)

	table.insert(tweenlist,"done")
	table.insert(tweenedlist,"done")
end
--Gets the laser pointer coords from the player
game.ReplicatedStorage.RemoteEvents.cast.OnServerEvent:Connect(function(player,pos)
	mousepos=pos
end)
local killob=nil
while wait() do
    --Kills players when the main body touches them
	if not killob and killable then
		for _,v in game.Players:GetPlayers() do
			char=v.Character
			if char then
				local hrp=char.HumanoidRootPart
				if Vector3.new(hrp.CFrame.Position.X-workspace.Body.CFrame.Position.X,0,hrp.CFrame.Position.Z-workspace.Body.CFrame.Position.Z).Magnitude<size*restingDistance*1.5 then
					game.ReplicatedStorage.RemoteEvents.die:FireClient(v,"stop")
					workspace.sfx.death:Play()
					killob=Instance.new("Vector3Value")
					killob.Value=bodypos
					local tween=tweenservice:Create(killob,TweenInfo.new(1*size,Enum.EasingStyle.Linear),{Value=hrp.Position})
					tween:Play()
					killob:GetPropertyChangedSignal("Value"):Connect(function()
						bodypos=killob.Value
					end)
					tween.Completed:Connect(function()
						game.ReplicatedStorage.RemoteEvents.die:FireClient(v,"die")
						task.wait(0.5)
						v:LoadCharacter()
						task.delay(5,function()
							killob=nil
						end)
					end)
				end
			end
		end
	end
    --Straightens all limbs
	for i,v in base do
		v.Target=bodypos
		v:Straighten(rotateVector(look,rodir[i]))
	end
	if (bodypos-Vector3.new(mousepos.X,bodypos.Y,mousepos.Z)).Magnitude>2 then
        --The target is far enough away, chase
		resting=false
		look=look:Lerp(Vector3.new(mousepos.X-bodypos.X,0,mousepos.Z-bodypos.Z).Unit,0.05/size*speed)
		if not killob then
			bodypos+=math.min(0.5*speed,(bodypos-Vector3.new(mousepos.X,bodypos.Y,mousepos.Z)).Magnitude)*look
		end
	else
		if not resting then
			resting=true
			for i,v in feet do
				v.resetQueue=true
			end
		end
	end
	local h=0
	for i,v in feet do
        --Do the thing
		v:Ground(i,true)
		h+=v.feetHeight
	end
    --Bop up and down
	bodypos=bodypos:lerp(Vector3.new(bodypos.X,h/4+bodyheight*size,bodypos.Z),0.1*speed)
	for _,v in segments do
		v:Display()
	end
	workspace.Body.CFrame=CFrame.new(bodypos)*CFrame.fromOrientation(look.X,0,look.Z)
	workspace.Body.Size=Vector3.new(4,4,4)*size
    --Guess I never fixed the bandaint solution. Tween between the current feet position and the target, and getting a progress timestamp between 1 and 0 for the sine wave to use
	for i,v in tweenlist do
		if typeof(v)=="Vector3" then
			local numval=Instance.new("Vector3Value")
			
			--bandaid solution
			numval.Value=feet[i].Target
			--
			
			local tween=tweenservice:Create(numval,TweenInfo.new(0.2/speed*size,Enum.EasingStyle.Linear),{Value=v})
			tweenlist[i]=tween
			tweenedlist[i]=numval
			tween:Play()
			tween.Completed:Connect(function()
				tweenlist[i]="done"
				if typeof(tweenedlist[i])=="Instance" then
					tweenedlist[i]:Destroy()
				end
				tweenedlist[i]="done"
			end)
			numval:GetPropertyChangedSignal("Value"):Connect(function()
				feet[i].Target=tweenedlist[i].Value
			end)
		end
	end
end
--game.StarterGui.ScreenGui.TextLabel.Text = "Commands(No prefix): \nbegin: take control of the spider. Click to move it around \ncancel: End horror mode \ndash: speed up \nkill: toggle killing upon touching on or off(default:off) \nfog <number>: sets the fog distance \nsize <number>: set the scale of the spider. Also affects sounds. No limits. May glitch upon first changing the size, but move around a bit and it'll fix itself(default:1) \nspeed <number>: set the speed of the spider. Might break things if the speed is too much higher than the size. Reset if it does(default:1)  \nreset: Resets the goal and body position\n have fun"