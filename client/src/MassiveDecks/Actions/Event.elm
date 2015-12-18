module MassiveDecks.Actions.Event where

import MassiveDecks.Models.Game exposing (..)
import MassiveDecks.Models.Player exposing (..)
import MassiveDecks.Models.Card exposing (..)
import MassiveDecks.Util as Util


type Event
  = PlayerJoin Id
  | PlayerStatus Id Status
  | PlayerLeft Id
  | PlayerDisconnect Id
  | PlayerReconnect Id
  | PlayerScore Id Int
  | RoundStart Call Id
  | RoundPlayed Int
  | RoundJudging (List PlayedCards)
  | RoundEnd Call Id (List PlayedCards) PlayedByAndWinner


{-| Generate events from a given change in lobby. -}
events : Lobby -> Lobby -> List Event
events oldLobby newLobby = List.concat
  [ diffPlayers oldLobby.players newLobby.players
  , diffRound oldLobby.round newLobby.round
  ]


{-| Generate events when joining an in-progress lobby to catch up. -}
catchUpEvents : Lobby -> List Event
catchUpEvents lobby =
  case lobby.round of
    Just round ->
      case round.responses of
        Hidden count -> [ roundPlayed count ]
        Revealed _ -> []
    Nothing ->
      []


diffPlayers : List Player -> List Player -> List Event
diffPlayers oldPlayers newPlayers =
  List.concatMap (diffPlayer oldPlayers) newPlayers

diffPlayer : List Player -> Player -> List Event
diffPlayer oldPlayers newPlayer =
  let
    id = newPlayer.id
    oldPlayer = List.filter (\player -> player.id == id) oldPlayers |> List.head
  in
    case oldPlayer of
      Just oldPlayer ->
        List.concat
          [ if oldPlayer.status /= newPlayer.status then  [ playerStatus newPlayer ] else []
          , if oldPlayer.score /= newPlayer.score then [ playerScore newPlayer ] else []
          , if (not oldPlayer.left) && newPlayer.left then [ playerLeft newPlayer ] else []
          , if (not oldPlayer.disconnected) && newPlayer.disconnected then [ playerDisconnect newPlayer ] else []
          , if oldPlayer.disconnected && (not newPlayer.disconnected) then [ playerReconnect newPlayer ] else []
          ]

      Nothing ->
        Util.apply [ playerJoin, playerStatus, playerScore ] newPlayer


diffRound : Maybe Round -> Maybe Round -> List Event
diffRound oldRound newRound =
  let
    differentRound = Maybe.map .call oldRound /= Maybe.map .call newRound
  in
    if differentRound then
      List.filterMap identity
        [ oldRound `Maybe.andThen` roundEnd
        , Maybe.map roundStart newRound
        , newRound `Maybe.andThen` (\newRound -> case newRound.responses of
            Hidden count -> Just (roundPlayed count)
            Revealed _ -> Nothing)
        ]
    else
      Maybe.map2 changedRound oldRound newRound |> Maybe.withDefault []

changedRound : Round -> Round -> List Event
changedRound oldRound newRound =
  case oldRound.responses of
    Hidden oldCount ->
      case newRound.responses of
        Hidden newCount -> if (oldCount < newCount) then [ roundPlayed (newCount - oldCount) ] else []
        Revealed _ -> [ roundJudging newRound ]
    Revealed _ ->
      []


{- Event Constructors -}

playerJoin : Player -> Event
playerJoin player = PlayerJoin player.id

playerReconnect : Player -> Event
playerReconnect player = PlayerReconnect player.id

playerStatus : Player -> Event
playerStatus player = PlayerStatus player.id player.status

playerScore : Player -> Event
playerScore player = PlayerScore player.id player.score

playerLeft : Player -> Event
playerLeft player = PlayerLeft player.id

playerDisconnect : Player -> Event
playerDisconnect player = PlayerDisconnect player.id

roundStart : Round -> Event
roundStart round = RoundStart round.call round.czar

roundPlayed : Int -> Event
roundPlayed amount = RoundPlayed amount

roundJudging : Round -> Event
roundJudging round =
  let
    responses = case round.responses of
      Hidden _ -> Nothing
      Revealed responses -> Just responses
    played = Maybe.map .cards responses |> Maybe.withDefault []
  in
    RoundJudging played

roundEnd : Round -> Maybe Event
roundEnd round =
  let
    responses = case round.responses of
      Hidden _ -> Nothing
      Revealed responses -> Just responses
    played = Maybe.map .cards responses
    playedByAndWinner = responses `Maybe.andThen` .playedByAndWinner
  in
    Maybe.map2 (RoundEnd round.call round.czar) played playedByAndWinner
