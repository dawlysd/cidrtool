module Main exposing (..)

import Bitwise
import Html exposing (..)


main =
    Html.program
        { init = init
        , view = view
        , update = update
        , subscriptions = always Sub.none
        }



-- CIDR HACKS


type alias Ip =
    Int



-- TODO(bkeyes): convert this to an opaque, internal type?


type Cidr
    = Cidr Ip Int


ipFromString : String -> Result String Ip
ipFromString addr =
    let
        checkOctet : Int -> Result String Int
        checkOctet i =
            if i > 255 || i < 0 then
                Err "invalid address (octet out of range)"
            else
                Ok i

        mergeOctets : Int -> List String -> Result String Ip
        mergeOctets ip octets =
            case octets of
                [] ->
                    Ok ip

                octet :: rest ->
                    String.toInt octet
                        |> Result.andThen checkOctet
                        |> Result.map (\i -> Bitwise.or ip (Bitwise.shiftLeftBy (8 * List.length rest) i))
                        |> Result.andThen (\ip -> mergeOctets ip rest)

        octets =
            String.split "." addr
    in
    if List.length octets == 4 then
        mergeOctets 0 octets
    else
        Err "invalid address (too many octets)"


ipToString : Ip -> String
ipToString ip =
    let
        octetToString i =
            toString (Bitwise.and 0xFF (Bitwise.shiftRightBy i ip))
    in
    String.join "." (List.map octetToString [ 24, 16, 8, 0 ])


makeCidr : Ip -> Int -> Cidr
makeCidr addr bits =
    if bits == 0 then
        Cidr 0 0
    else
        Cidr (Bitwise.and addr (Bitwise.shiftLeftBy (32 - bits) 0xFFFFFFFF)) bits


cidrFromString : String -> Result String Cidr
cidrFromString s =
    let
        split : String -> Result String ( String, String )
        split s =
            case String.split "/" s of
                [ addr, mask ] ->
                    Ok ( addr, mask )

                _ ->
                    Err "invalid CIDR block (bad format)"

        checkMask : Int -> Result String Int
        checkMask m =
            if m > 32 || m < 0 then
                Err "invalid CIDR block (mask out of range)"
            else
                Ok m

        parseMask : String -> Result String Int
        parseMask mask =
            String.toInt mask |> Result.andThen checkMask
    in
    split s
        |> Result.andThen (\( addr, mask ) -> Result.map2 makeCidr (ipFromString addr) (parseMask mask))


cidrToString : Cidr -> String
cidrToString (Cidr addr mask) =
    ipToString addr ++ "/" ++ toString mask


address : Cidr -> Ip
address (Cidr addr _) =
    addr


maskBits : Cidr -> Int
maskBits (Cidr _ mask) =
    mask


firstAddress : Cidr -> Ip
firstAddress (Cidr addr _) =
    addr


nextAddress : Cidr -> Ip
nextAddress (Cidr addr mask) =
    if mask == 0 then
        0
    else
        addr + Bitwise.shiftLeftBy (32 - mask) 1


lastAddress : Cidr -> Ip
lastAddress cidr =
    nextAddress cidr - 1


inBlock : Cidr -> Ip -> Bool
inBlock cidr ip =
    firstAddress cidr <= ip && ip < nextAddress cidr


intersects : Cidr -> Cidr -> Bool
intersects cidr other =
    let
        test : Cidr -> Cidr -> Bool
        test x y =
            firstAddress x >= firstAddress y && firstAddress x < nextAddress y
    in
    test cidr other || test other cidr


subtract : Cidr -> List Cidr -> List Cidr
subtract minuend subtrahends =
    let
        toRanges : List Cidr -> List ( Ip, Ip )
        toRanges cidrs =
            cidrs
                |> List.filter (intersects minuend)
                |> List.sortBy firstAddress
                |> List.map (\c -> ( firstAddress c, nextAddress c ))

        largestFit : Ip -> Ip -> Int -> Maybe Cidr
        largestFit start end bits =
            let
                candidate = makeCidr start bits
            in
            if start >= end then
                Nothing
            else if nextAddress candidate <= end && firstAddress candidate == start then
                Just candidate
            else
                largestFit start end (bits + 1)

        fill : Ip -> Ip -> Int -> List Cidr
        fill start end bits =
            case largestFit start end bits of
                Nothing ->
                    []

                Just cidr ->
                    cidr :: fill (nextAddress cidr) end bits

        reduce : ( Ip, Ip ) -> ( Ip, List (List Cidr) ) -> ( Ip, List (List Cidr) )
        reduce ( to, next ) ( start, r ) =
            ( next, fill start to (maskBits minuend) :: r )
    in
        toRanges subtrahends ++ [ ( nextAddress minuend, 0xFFFFFFFF ) ]
            |> List.foldl reduce ( address minuend, [] )
            |> Tuple.second
            |> List.concat
            |> List.sortBy firstAddress


-- END CIDR HACKS


type alias Model =
    { cidr : Cidr
    }


init : ( Model, Cmd Msg )
init =
    ( Model (Cidr 0 0), Cmd.none )


type Msg
    = DoNothing


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        DoNothing ->
            ( model, Cmd.none )


view : Model -> Html Msg
view model =
    div []
        [ text (cidrToString (Result.withDefault (Cidr 0 0) (cidrFromString "192.168.1.4/31")))
        ]
