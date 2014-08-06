module DebuggerInterface where

import Window
import Graphics.Input (..)
import Debug
import Slider (..)

-- Model

type Update =
    { window : (Int, Int)
    , paused : Bool
    , restart : Bool
    , maxEvents : Int
    , scrub : Int
    }

type State =
    { paused : Bool
    , events : (Int, Int)
    }

pausedInput : Input Bool
pausedInput = input False

restartInput : Input ()
restartInput = input ()

scrubInput : Input Int
scrubInput = input 0

port eventCounter : Signal Int

-- When we restart at any time we need to be notified of what state to go to.
port restartPort : Signal Bool

-- View

objHeight = 40
buttonWidth = 40

playButton : Element
playButton =
    let icon = [ngon 3 15.0 |> filled red]
    in  collage buttonWidth objHeight icon
            |> clickable pausedInput.handle False

pauseButton : Element
pauseButton =
    let icon = [ rect 7.5 20
                    |> filled red
                    |> moveX -6
               , rect 7.5 20
                    |> filled red
                    |> moveX 6
                ]
    in collage buttonWidth objHeight icon
            |> clickable pausedInput.handle True

restartButton : Element
restartButton =
    let icon = [circle 15.0 |> filled orange]
    in  collage buttonWidth objHeight icon
            |> clickable restartInput.handle ()

scrubSlider : (Int, Int) -> State -> Element
scrubSlider (w,_) state =
    let leftOffset = sum <| map widthOf [playButton, restartButton]
        sliderLength = w - leftOffset
        sliderStyle =
            { defaultSlider
            | length <- sliderLength
            , max <- toFloat <| snd state.events
            , value <- toFloat <| fst state.events
            , disabled <- not state.paused
            }
    in  container sliderLength objHeight midLeft
            <| slider scrubInput.handle round sliderStyle

view : (Int, Int) -> State -> Element
view dim state =
    (if state.paused then playButton else pauseButton)
    `beside` restartButton
    `beside` scrubSlider dim state

-- The wiring

main : Signal Element
main = lift2 view Window.dimensions scene

port scrubTo : Signal Int
port scrubTo = scrubInput.signal

port pause : Signal Bool
port pause = pausedInput.signal

port restart : Signal Int
port restart = lift (\x -> 0) restartInput.signal

scene : Signal State
scene = foldp step startState aggregateUpdates

startState : State
startState =
    { paused = False
    , events = (0,0)
    }

step : Update -> State -> State
step update state =
    if  | update.restart ->
            Debug.log "restart" startState
        | otherwise ->
            if  | update.paused ->
                    { paused = update.paused
                    , events = (update.scrub, update.maxEvents)
                    }
                | otherwise ->
                    { paused = update.paused
                    , events = (update.maxEvents, update.maxEvents)
                    }

aggregateUpdates : Signal Update
aggregateUpdates =
    let dampenedEvents = keepWhen (lift not pausedInput.signal) 0 eventCounter
        aggregator window paused restart eventCounter scrubPosition =
            { window = window
            , paused = paused
            , restart = restart
            , maxEvents = eventCounter
            , scrub = scrubPosition
            }
    in  aggregator <~ Window.dimensions
                    ~ pausedInput.signal
                    ~ restartPort
                    ~ dampenedEvents
                    ~ scrubInput.signal
