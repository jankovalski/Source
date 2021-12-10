class SpeechCommandInterface extends CommandInterface
    implements  ISpeechClient;

import enum SpeechRecognitionConfidence from Engine.SpeechManager;

var private array<Focus>	PhraseStartFoci;  //the CommandInterface's list of Foci at the start of a speech phrase
var private int				PhraseStartFociLength;
var private array<Focus>	RecognitionFoci;  //the CommandInterface's list of Foci at the recognition of a speech phrase
var private int				RecognitionFociLength;

simulated function Initialize()
{
	Super.Initialize();
	RegisterSpeechRecognition();
}

simulated function Destroyed()
{
	Super.Destroyed();
	UnregisterSpeechRecognition();
}

simulated function RegisterSpeechRecognition()
{
	Level.GetEngine().SpeechManager.RegisterInterest(self);
}

simulated function UnregisterSpeechRecognition()
{
	Level.GetEngine().SpeechManager.UnRegisterInterest(self);
}

simulated protected function PostDeactivated()
{
	Super.PostDeactivated();
	UnregisterSpeechRecognition();
}

simulated function ProcessRule(name Rule, name Value)
{
	local int i;

	switch (Rule)
	{
		case 'Team':
			switch (Value)
			{
				case 'RedTeam':
					SetCurrentTeam(RedTeam);
					break;
				case 'BlueTeam':
					SetCurrentTeam(BlueTeam);
					break;
				case 'Element':
					SetCurrentTeam(Element);
					break;
			}
			break;

		case 'HoldRecognizedCommand':
			for (i=0; i<Commands.Length - 1; ++i)
			{
				if (GetEnum(ECommand, Commands[i].Command) == Value)
				{
					log("[SPEECHCOMMAND] Held speech command"@GetEnum(ECommand, Commands[i].Command));
					GiveCommand(Commands[i], true);
					break;
				}
			}
			break;

		case 'Command':
			for (i=0; i<Commands.Length - 1; ++i)
			{
				if (GetEnum(ECommand, Commands[i].Command) == Value)
				{
					log("[SPEECHCOMMAND] Recognized speech command"@GetEnum(ECommand, Commands[i].Command));
					GiveCommand(Commands[i], false);
					break;
				}
			}
			break;

		default:
			log("[SPEECHCOMMAND] Unknown rule.");
	}
}

//ISpeechClient implementation
simulated function OnSpeechPhraseStart()
{
	log("[SPEECHCOMMAND] Speech phrase start outside of state.");
}

//called by the speech recognition system when a speech command is recognized
simulated function OnSpeechCommandRecognized(name Rule, Array<name> Value, SpeechRecognitionConfidence Confidence)
{
	log("[SPEECHCOMMAND] Speech recognised outside of state.");
}

function OnSpeechFalseRecognition()
{
	log("[SPEECHCOMMAND] False recognition outside of state.");
}

function OnSpeechAudioLevel(int Value)
{
}

// CommandInterface overrides
simulated function bool ShouldSpeakTeam()
{
	return false;
}

simulated function bool ShouldSpeak()
{
	return false;
}

simulated function GiveCommandSP()
{
	local CommandInterface CurrentCommandInterface;
	local SwatGamePlayerController Player;

	// get the current graphic command interface
    Player = SwatGamePlayerController(Level.GetLocalPlayerController());
    CurrentCommandInterface = Player.GetCommandInterface();

	CurrentCommandInterface.CurrentSpeechCommand = GetColorizedCommandText(PendingCommand);
	CurrentCommandInterface.CurrentSpeechCommandTime = Player.Level.TimeSeconds + 2;

	Super.GiveCommandSP();
}

simulated function GiveCommandMP()
{
	// should never get here
	log("[SPEECHCOMMAND] Error - in multiplayer.");
}

function StartCommand()
{
    if (SwatRepo(Level.GetRepo()).GuiConfig.SwatGameState != GAMESTATE_MidGame)
    {
        GotoState('');
        return;
    }

    SendCommandToOfficers();
}

// override - this interface just re-uses the current command interface's foci
simulated function PostUpdate(SwatGamePlayerController Player)
{
	Super.PostUpdate(Player);

	Foci = Player.GetCommandInterface().Foci;
	FociLength = Player.GetCommandInterface().FociLength;
	LastFocusUpdateOrigin = Player.GetCommandInterface().LastFocusUpdateOrigin;
}

// override - return the focus the player was viewing at the start of speech if it was a better match
simulated protected function Actor GetPendingCommandTargetActor()
{
	local Actor FocusActor;

	// try foci at recognition
	PendingCommandFoci = RecognitionFoci;
	PendingCommandFociLength = RecognitionFociLength;
	log("[SPEECHCOMMAND] Try recognition foci ("$PendingCommandFoci[0].Actor$")");
	FocusActor = Super.GetPendingCommandTargetActor();

	if (FocusActor == None)
	{
		// try foci at phrase start
		PendingCommandFoci = PhraseStartFoci;
		PendingCommandFociLength = PhraseStartFociLength;
		log("[SPEECHCOMMAND] Try phrase start foci ("$PendingCommandFoci[0].Actor$")");
		FocusActor = Super.GetPendingCommandTargetActor();
	}
	
	return FocusActor;
}

// States
// We are waiting for speech input from the user
auto state WaitingForSpeech
{
	simulated function OnSpeechPhraseStart()
	{
		// save foci at time of phrase start detection
		PhraseStartFoci = Foci;
		PhraseStartFociLength = FociLength;

		log("[SPEECHCOMMAND] Begin recognition, got phrase start foci"@PhraseStartFociLength);
		GotoState('ProcessingSpeech');
	}

	simulated function OnSpeechCommandRecognized(name Rule, Array<name> Value, SpeechRecognitionConfidence Confidence)
	{
		// do nothing
	}

	function OnSpeechFalseRecognition()
	{
		// who cares?
	}
}

// Speech is being received and decoded
state ProcessingSpeech
{
	simulated function OnSpeechPhraseStart()
	{
		// do nothing
	}

	simulated function OnSpeechCommandRecognized(name Rule, Array<name> Value, SpeechRecognitionConfidence Confidence)
	{
		// save foci at time of recognition
		RecognitionFoci = Foci;
		RecognitionFociLength = FociLength;

		switch (Rule)
		{
			case 'TeamAndCommand':
				ProcessRule('Team', Value[0]);
				ProcessRule('Command', Value[1]);
				break;

			case 'HoldCommand':
				ProcessRule('HoldRecognizedCommand', Value[1]);
				break;

			case 'TeamAndHoldCommand':
				ProcessRule('Team', Value[0]);
				ProcessRule('HoldRecognizedCommand', Value[2]);
				break;

			default:
				ProcessRule(Rule, Value[0]);
				break;
		}

		GotoState('WaitingForSpeech');
	}

	function OnSpeechFalseRecognition()
	{
		log("[SPEECHCOMMAND] Bad speech.");
		GotoState('WaitingForSpeech');
	}
}

defaultproperties
{
    bStatic=false
    Physics=PHYS_None
    bStasis=true

	AlwaysPostUpdate = true
	ValidateCommandFocus = false;

    CommandClass=class'Command_SP'
    StaticCommandsClass=class'CommandInterfaceStaticCommands_SP'
    MenuInfoClass=class'CommandInterfaceMenuInfo_SP'
    ContextsListClass=class'CommandInterfaceContextsList_SP'
    ContextClass=class'CommandInterfaceContext_SP'
    DoorRelatedContextClass=class'CommandInterfaceDoorRelatedContext_SP'
}
