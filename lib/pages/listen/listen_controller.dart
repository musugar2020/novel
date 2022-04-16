import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:novel/pages/listen/listen_model.dart';
import 'package:novel/router/app_pages.dart';
import 'package:novel/services/listen.dart';
import 'package:novel/utils/database_provider.dart';

class ListenController extends SuperController
    with GetSingleTickerProviderStateMixin {
  TextEditingController textEditingController = TextEditingController();

  List<Item> chapters = List.empty(growable: true);
  RxList<Search>? searchs = RxList<Search>();
  List<Search> history = List.empty(growable: true);
  Rx<Search> model = Search().obs;
  String url = "";
  late AudioPlayer audioPlayer;
  Rx<Duration>? cache = Duration(seconds: 0).obs;
  Rx<ProcessingState> playerState = ProcessingState.idle.obs;
  RxBool moving = false.obs;
  RxBool playing = false.obs;
  RxBool useProxy = false.obs;
  RxBool getLink = false.obs;
  RxBool syncPosition = false.obs;
  final bgColor = Colors.transparent.obs;
  RxInt idx = 0.obs;
  RxDouble fast = (1.0).obs;
  late ScrollController? scrollcontroller;

  late TabController tabController;

  final tabs = ["当前播放", "播放历史"];
  bool preload = false;
  @override
  void onInit() {
    super.onInit();

    audioPlayer = AudioPlayer();
    scrollcontroller = ScrollController();
    tabController =
        TabController(initialIndex: 0, length: tabs.length, vsync: this);
    ever(idx, (_) {
      scrollcontroller = ScrollController(initialScrollOffset: idx.value * 40);
      model.value.idx = idx.value;
    });

    ever(fast, (_) {
      audioPlayer.setSpeed(fast.value);
    });

    init();

    audioPlayer.playerStateStream.listen((state) {
      saveState();

      playerState.value = state.processingState;
      Get.log(
          "state >>>>>>${state.processingState}  playing >>>>${state.playing}");
      playing.value =
          state.playing && state.processingState != ProcessingState.idle;

      switch (state.processingState) {
        case ProcessingState.idle:
          break;
        case ProcessingState.loading:
          break;
        case ProcessingState.buffering:
          break;
        case ProcessingState.ready:
          break;
        case ProcessingState.completed:
          syncPosition.value = false;
          next();
          break;
      }
    });

    audioPlayer.positionStream.listen((Duration p) {
      if (!moving.value) {
        if (audioPlayer.playing &&
            playerState.value != ProcessingState.completed) {
          // Get.log(playerState.value.name);

          model.update((val) {
            val!.position = p;
          });
        }
      }
    });

    audioPlayer.bufferedPositionStream.listen((event) {
      cache!.value = event;
    });
  }

  getBackgroundColor() async {
    // print("start get backgroud color");
    // PaletteGenerator paletteGenerator =
    //     await PaletteGenerator.fromImageProvider(
    //   ExtendedNetworkImageProvider(
    //     "https://img.ting55.com/${DateUtil.formatDateMs(model.value.addtime ?? 0, format: "yyyy/MM")}/${model.value.picture}!300",
    //   ),
    // );
    // bgColor.value = paletteGenerator.dominantColor!.color;
  }

  initHitory() async {
    // await DataBaseProvider.dbProvider.clear();
    history = await DataBaseProvider.dbProvider.voices();
  }

  init() async {
    await initHitory();
    if (history.isNotEmpty) {
      model.value = history.first;
      idx.value = model.value.idx!;
      getUrl(idx.value);

      detail(model.value.id.toString());

      // getBackgroundColor();
    }
  }

  @override
  void onReady() {}

  @override
  void onClose() {
    saveState();

    audioPlayer.dispose();
    textEditingController.dispose();
    tabController.dispose();
  }

  saveState() async {
    if ((model.value.id ?? "").isNotEmpty) {
      model.value.idx = idx.value;
      model.update((val) {
        val!.count = chapters.length;
        val.idx = idx.value;
      });
      await DataBaseProvider.dbProvider.addVoice(model.value);
    }
  }

  clear() {
    searchs!.clear();
    textEditingController.clear();
  }

  detail(String id) async {
    chapters = await ListenApi().getChapters(id);
    model.update((val) {
      val!.count = searchs!.length;
    });
  }

//搜索
  search(String v) async {
    if (v.isEmpty) return;
    searchs!.clear();
    searchs!.value = (await ListenApi().search(v))!;
  }

  //跳转
  toPlay(int i) async {
    Get.toNamed(AppRoutes.listen);
    await audioPlayer.stop();
    saveState();
    //
    var pickSearch = searchs![i];
    await detail(pickSearch.id.toString());
    Search? v = await DataBaseProvider.dbProvider
        .voiceById(int.parse(pickSearch.id.toString()));

    if (v != null) pickSearch = v;
    model.value = pickSearch;

    idx.value = model.value.idx ?? 0;
    // controller.getBackgroundColor();
    playerState.value = ProcessingState.idle;

    clear();
    await getUrl(i);

    // await audioPlayer.play();
  }

  getUrl(int i) async {
    getLink.value = true;
    try {
      url = await ListenApi().chapterUrl(chapters[i].link);
    } catch (e) {
      print(e);
    }
    getLink.value = false;

    // url =
    //     'https://pp.ting55.com/202201261454/cf07754102fc5c1a60aee3f712f6358d/2015/12/3705/4.mp3';
    print("audio url $url");
    if (url.isEmpty) {
      BotToast.showText(text: "获取资源链接失败,请重试...");
      return;
    }
    model.value.url = url;
    // if (audioPlayer.playing) {
    //   audioPlayer.stop();
    // }
    try {
      await audioPlayer.setAudioSource(
        AudioSource.uri(
          Uri.parse(url),
          tag: MediaItem(
            id: '1',
            album: model.value.title,
            title: "${model.value.title}-第${idx.value + 1}回",
            artUri: Uri.parse(model.value.cover ?? ""),
          ),
        ),
      );
      var duration = (await audioPlayer.load())!;
      model.update((val) async {
        val!.duration = duration;
      });

      await audioPlayer.seek(model.value.position);
    } on PlayerException catch (e) {
      print("Error code: ${e.code}");

      print("Error message: ${e.message}");
      playerState.value = ProcessingState.idle;
      playing.value = false;
      BotToast.showText(text: "加载音频资源失败,请重试....");
    } on PlayerInterruptedException catch (e) {
      print("Connection aborted: ${e.message}");
      await audioPlayer.pause();
    } catch (e) {
      print(e);
    }
    return 1;
  }

  playToggle() async {
    if (playerState.value == ProcessingState.ready) {
      if (playing.value) {
        await audioPlayer.pause();
      } else {
        await audioPlayer.play();
      }
    } else {
      BotToast.showText(text: '加载资源中...');

      await getUrl(idx.value);
      await audioPlayer.play();
    }
  }

  pre() async {
    if (idx.value == 0) {
      return;
    }

    cache!.value = Duration.zero;
    await Future.delayed(Duration(seconds: 1));
    model.update((val) {
      val!.position = Duration.zero;
    });
    int result = await getUrl(idx.value - 1);
    if (result == 1) {
      idx.value = idx.value - 1;
      await audioPlayer.play();
    }
  }

  next() async {
    Get.log('next');
    if (idx.value == chapters.length - 1) {
      return;
    }
    await Future.delayed(
        Duration(seconds: 1), () => BotToast.showText(text: '播放下一集'));

    cache!.value = Duration.zero;
    model.update((val) {
      val!.position = Duration.zero;
    });
    int result = await getUrl(idx.value + 1);
    if (result == 1) {
      idx.value = idx.value + 1;
      await audioPlayer.play();
    }
  }

  movePosition(double v) async {
    // if (!audioPlayer.playing) return;

    model.update((val) {
      val!.position = Duration(seconds: v.toInt());
    });
  }

  changeEnd(double value) async {
    if (playerState.value == ProcessingState.idle) return;

    moving.value = false;
    var x = Duration(seconds: value.toInt());
    model.update((val) {
      val!.position = x;
    });

    await audioPlayer.seek(x);
  }

  changeStart() {
    if (playerState.value == ProcessingState.idle) return;

    moving.value = true;
  }

  forward() async {
    if (playerState.value == ProcessingState.idle) return;

    model.update((val) {
      val!.position = Duration(
          seconds: min(model.value.position!.inSeconds + 10,
              model.value.duration!.inSeconds));
    });
    await audioPlayer.seek(model.value.position);
  }

  replay() async {
    if (playerState.value == ProcessingState.idle) return;

    model.update((val) {
      val!.position =
          Duration(seconds: max(0, model.value.position!.inSeconds - 10));
    });
    await audioPlayer.seek(model.value.position);
  }

  @override
  void onInactive() {
    // TODO: implement onInactive
    // audioPlayer.pause();

    saveState();
  }

  @override
  void onPaused() {
    // TODO: implement onPaused
  }

  @override
  void onResumed() {
    // TODO: implement onResumed
    // audioPlayer.resume();
  }

  @override
  void onDetached() {
    // TODO: implement onDetached
  }
}
