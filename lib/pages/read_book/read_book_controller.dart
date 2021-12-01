import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_statusbar_manager/flutter_statusbar_manager.dart';
import 'package:get/get.dart';
import 'package:novel/common/animation/AnimationControllerWithListenerNumber.dart';
import 'package:novel/common/screen.dart';
import 'package:novel/common/values/setting.dart';
import 'package:novel/global.dart';
import 'package:novel/pages/book_chapters/chapter.pb.dart';
import 'package:novel/pages/home/home_controller.dart';
import 'package:novel/pages/home/home_model.dart';
import 'package:novel/pages/read_book/NovelPagePainter.dart';
import 'package:novel/pages/read_book/ReaderPageManager.dart';
import 'package:novel/pages/read_book/read_book_model.dart';
import 'package:novel/services/book.dart';
import 'package:novel/utils/chapter_parse.dart';
import 'package:novel/utils/database_provider.dart';
import 'package:novel/utils/local_storage.dart';
import 'package:novel/utils/text_composition.dart';

enum LOAD_STATUS { LOADING, FAILED, FINISH }

class ReadBookController extends FullLifeCycleController
    with FullLifeCycle, SingleGetTickerProviderMixin {
  Book? book;
  Rx<LOAD_STATUS> loadStatus = LOAD_STATUS.LOADING.obs;
  RxBool saveReadState = true.obs;
  RxBool inShelf = false.obs;
  RxList chapters = List.empty().obs;
  RxBool showMenu = false.obs;
  double? electricQuantity = 1.0;
  ReadSetting? setting;
  Paint bgPaint = Paint();
  NovelPagePainter? mPainter;
  TouchEvent currentTouchEvent = TouchEvent(TouchEvent.ACTION_UP, Offset.zero);
  AnimationController? animationController;
  GlobalKey canvasKey = new GlobalKey();

  /// 翻页动画类型
  int currentAnimationMode = ReaderPageManager.TYPE_ANIMATION_COVER_TURN;
  //
  ReadPage? prePage;
  ReadPage? curPage;
  ReadPage? nextPage;
  //
  HomeController? homeController;
  @override
  void onInit() {
    super.onInit();
    homeController = Get.find<HomeController>();
    String bookId = Get.arguments['id'].toString();
    if (bookId.isEmpty) {
      book = Book.fromJson(Get.arguments['bookJson']);
    } else {
      book = homeController!.getBookById(bookId);
      inShelf.value = true;
    }
    setting = Get.find<HomeController>().setting;
    initReadConfig();
    initData();

    FlutterStatusbarManager.setFullscreen(true);
  }

  initReadConfig() {
    switch (currentAnimationMode) {
      case ReaderPageManager.TYPE_ANIMATION_SIMULATION_TURN:
      case ReaderPageManager.TYPE_ANIMATION_COVER_TURN:
        animationController = AnimationControllerWithListenerNumber(
          vsync: this,
        );
        break;
      case ReaderPageManager.TYPE_ANIMATION_SLIDE_TURN:
        animationController = AnimationControllerWithListenerNumber.unbounded(
          vsync: this,
        );
        break;
    }

    if (animationController != null) {
      ReaderPageManager pageManager = ReaderPageManager();
      pageManager.setCurrentAnimation(currentAnimationMode);
      pageManager.setCurrentCanvasContainerContext(canvasKey);
      pageManager.setAnimationController(animationController!);
      pageManager.setContentViewModel(this);
      mPainter = NovelPagePainter(pageManager: pageManager);
    }
    mPainter = mPainter;
  }

  initData() async {
    // try {
    chapters.value = await DataBaseProvider.dbProvider.getChapters(book!.id);
    if (chapters.isEmpty) {
      //初次打开
      await getReadRecord();
      await getChapter();
    } else {
      getChapter();
    }
    await initContent(book!.chapterIdx!, false);
    await cur();
    loadStatus.value = LOAD_STATUS.FINISH;
    // } catch (e) {
    //   loadStatus.value = LOAD_STATUS.FAILED;
    //   print(e);
    // }
  }

  initContent(int idx, bool jump) async {
    curPage = await loadChapter(idx);

    loadChapter(idx + 1).then((value) => {nextPage = value});

    loadChapter(idx - 1).then((value) => {prePage = value});

    if (jump) {
      book!.pageIdx = 0;
      canvasKey.currentContext?.findRenderObject()?.markNeedsPaint();
    }
  }

  loadChapter(int idx) async {
    ReadPage readPage = ReadPage();
    if (idx < 0 || idx >= chapters.length) {
      return readPage;
    }
    var chapter = chapters[idx];
    readPage.chapterName = chapter.chapterName;
    readPage.chapterContent =
        await DataBaseProvider.dbProvider.getContent(chapter.chapterId);

    //获取章节内容
    if (readPage.chapterContent!.isEmpty) {
      readPage.chapterContent = await getChapterContent(idx);
      if (readPage.chapterContent!.isEmpty) {
        readPage.chapterContent = "章节内容加载失败,请重试.......\n";
      } else {
        await DataBaseProvider.dbProvider
            .updateContent(chapter.chapterId, readPage.chapterContent);
        chapters[idx].hasContent = "2";
      }
    }
    //获取分页数据
    //本地是否有分页的缓存
    var key = '${book!.id}pages${readPage.chapterName}';
    var pageData = LoacalStorage().getJSON(key);

    // if (pageData != null) {
    //   readPage.pages =
    //       pageData.map((e) => TextPage.fromJson(e)).toList().cast<TextPage>();
    //   LoacalStorage().remove(key);
    // } else {
    readPage.pages = TextComposition.parseContent(readPage, setting!);
    // }
    return readPage;
  }

  saveState() {
    if (saveReadState.value) {
      LoacalStorage()
          .setJSON('${book!.id}pages${prePage?.chapterName}', prePage?.pages);
      LoacalStorage()
          .setJSON('${book!.id}pages${curPage?.chapterName}', curPage?.pages);
      LoacalStorage()
          .setJSON('${book!.id}pages${nextPage?.chapterName}', nextPage?.pages);
      if (Global.profile!.token!.isNotEmpty) {
        BookApi().uploadReadRecord(
            Global.profile!.username, book!.id, book!.chapterIdx.toString());
      }
    }
  }

  getChapterContent(int idx) async {
    //从数据库中取
    var chapterId = chapters[idx].chapterId;
    var res = await BookApi().getContent(chapterId);
    String chapterContent = res['content'];
    if (chapterContent.isEmpty) {
      //本地解析
      chapterContent = await ChapterParseUtil().parseContent(res['link']);
      //上传到数据库
      BookApi().updateContent(chapterId, chapterContent);
    }

    return chapterContent;
  }

  /*页面点击事件 */
  void tapPage(TapUpDetails details) {
    var wid = Screen.width;
    var hSpace = Screen.height / 4;
    var space = wid / 3;
    var curWid = details.globalPosition.dx;
    var curH = details.globalPosition.dy;
    var location = details.localPosition;
    if ((curWid > space) && (curWid < 2 * space) && (curH < hSpace * 3)) {
      toggleShowMenu();
    } else if ((curWid > space * 2)) {
      if (setting!.leftClickNext ?? false) {
        clickPage(1, location);
        return;
      }
      clickPage(1, location);
    } else if ((curWid > 0 && curWid < space)) {
      if (setting!.leftClickNext ?? false) {
        clickPage(1, location);
        return;
      }
      clickPage(-1, location);
    }
  }

  //点击模拟滑动
  void clickPage(int f, Offset detail) {
    TouchEvent currentTouchEvent = TouchEvent(TouchEvent.ACTION_DOWN, detail);

    mPainter!.setCurrentTouchEvent(currentTouchEvent);

    var offset = Offset(
        f > 0
            ? (detail.dx - Screen.width / 15 - 5)
            : (detail.dx + Screen.width / 15 + 5),
        0);
    currentTouchEvent = TouchEvent(TouchEvent.ACTION_MOVE, offset);

    mPainter!.setCurrentTouchEvent(currentTouchEvent);

    currentTouchEvent = TouchEvent(TouchEvent.ACTION_CANCEL, offset);

    mPainter!.setCurrentTouchEvent(currentTouchEvent);
    canvasKey.currentContext!.findRenderObject()!.markNeedsPaint();
  }
  //章节切换
  // chapter

  getChapter() async {
    List<ChapterProto> cps =
        await BookApi().getChapters(book!.id, chapters.length);
    if (cps.isNotEmpty) {
      chapters.addAll(cps);
      DataBaseProvider.dbProvider.addChapters(cps, book!.id);
    }
  }

  getReadRecord() async {
    if (Global.profile!.token!.isNotEmpty) {
      book!.chapterIdx =
          await BookApi().getReadRecord(Global.profile!.username, book!.id);
    }
  }

  @override
  void onReady() {}

  @override
  void onClose() {
    saveState();
    super.onClose();
    animationController?.dispose();
    FlutterStatusbarManager.setFullscreen(false);
  }

  @override
  void onDetached() {
    // TODO: implement onDetached
  }

  @override
  void onInactive() {
    // TODO: implement onInactive
  }

  @override
  void onPaused() {
    print("挂起");
    saveState();
  }

  @override
  void onResumed() {
    print("恢复");
  }

  void toggleShowMenu() {
    showMenu.value = !showMenu.value;
  }

  bool isCanGoNext() {
    if (book!.chapterIdx! >= (chapters.length - 1)) {
      if (book!.pageIdx! >= (curPage!.pageOffsets - 1)) {
        return false;
      }
    }
    return next() != null;
  }

  bool isCanGoPre() {
    if (book!.chapterIdx! <= 0 && book!.pageIdx! <= 0) {
      return false;
    }
    return pre() != null;
  }

  getPageCacheKey(int? chapterIdx, int? pageIndex) {
    return book!.id.toString() + chapterIdx.toString() + pageIndex.toString();
  }

  cur() {
    var key = getPageCacheKey(book!.chapterIdx, book!.pageIdx);
    if (homeController!.widgets.containsKey(key)) {
      return homeController!.widgets[key];
    } else {
      Future.delayed(Duration(milliseconds: 200), () => preLoadWidget());
      return homeController!.widgets.putIfAbsent(
          key,
          () => TextComposition.drawContent(
                curPage,
                book!.pageIdx,
                Get.isDarkMode,
                setting,
                homeController!.bgImages![setting!.bgIndex ?? 0],
                electricQuantity,
              ));
    }
  }

  next() {
    var i = book!.pageIdx! + 1;
    var key = getPageCacheKey(book!.chapterIdx, i);

    if (homeController!.widgets.containsKey(key)) {
      return homeController!.widgets[key];
    } else {
      if (nextPage == null) {
        loadChapter(book!.chapterIdx! + 1).then((value) => {nextPage = value});
        return null;
      }
      return homeController!.widgets.putIfAbsent(
          key,
          () => i >= curPage!.pageOffsets
              ? TextComposition.drawContent(
                  nextPage,
                  0,
                  Get.isDarkMode,
                  setting,
                  homeController!.bgImages![setting!.bgIndex ?? 0],
                  electricQuantity,
                )
              : TextComposition.drawContent(
                  curPage,
                  i,
                  Get.isDarkMode,
                  setting,
                  homeController!.bgImages![setting!.bgIndex ?? 0],
                  electricQuantity,
                ));
    }
  }

  pre() {
    var i = book!.pageIdx! - 1;
    var key = getPageCacheKey(book!.chapterIdx, i);

    if (homeController!.widgets.containsKey(key)) {
      return homeController!.widgets[key];
    } else {
      if (prePage == null) {
        loadChapter(book!.chapterIdx! - 1).then((value) => prePage = value);
        return null;
      }
      return homeController!.widgets.putIfAbsent(
          key,
          () => i < 0
              ? TextComposition.drawContent(
                  prePage,
                  prePage!.pageOffsets - 1,
                  Get.isDarkMode,
                  setting,
                  homeController!.bgImages![setting!.bgIndex ?? 0],
                  electricQuantity,
                )
              : TextComposition.drawContent(
                  curPage,
                  i,
                  Get.isDarkMode,
                  setting,
                  homeController!.bgImages![setting!.bgIndex ?? 0],
                  electricQuantity,
                ));
    }
  }

  void changeCoverPage(int offsetDifference) {
    int idx = book?.pageIdx ?? 0;

    int curLen = (curPage?.pageOffsets ?? 0);
    if (idx == curLen - 1 && offsetDifference > 0) {
      Future.delayed(
          Duration(milliseconds: 500),
          () => {
                Battery()
                    .batteryLevel
                    .then((value) => electricQuantity = value / 100)
              });
      int tempCur = book!.chapterIdx! + 1;
      if (tempCur >= chapters.length) {
        Get.snackbar("", "已经是第一页", snackPosition: SnackPosition.TOP);
        return;
      } else {
        book!.chapterIdx = book!.chapterIdx! + 1;
        prePage = curPage;
        if ((nextPage?.chapterName ?? "") == "-1") {
          loadChapter(book!.chapterIdx ?? 0).then((value) => curPage = value);
        } else {
          curPage = nextPage;
        }
        book!.pageIdx = 0;
        nextPage = null;
        Future.delayed(Duration(milliseconds: 500), () {
          loadStatus.value = LOAD_STATUS.LOADING;
          loadChapter(book!.chapterIdx! + 1).then((value) => nextPage = value);
          loadStatus.value = LOAD_STATUS.FINISH;
        });

        return;
      }
    }
    if (idx == 0 && offsetDifference < 0) {
      Future.delayed(
          Duration(milliseconds: 500),
          () => {
                Battery()
                    .batteryLevel
                    .then((value) => electricQuantity = value / 100)
              });
      int tempCur = book!.chapterIdx! - 1;
      if (tempCur < 0) {
        Get.snackbar("", "第一页", snackPosition: SnackPosition.TOP);

        return;
      }
      nextPage = curPage;
      curPage = prePage;
      book!.chapterIdx = book!.chapterIdx! - 1;

      book!.pageIdx = curPage!.pageOffsets - 1;
      prePage = null;
      Future.delayed(Duration(milliseconds: 500), () {
        loadChapter(book!.chapterIdx! - 1).then((value) => prePage = value);
      });

      return;
    }
    offsetDifference > 0
        ? (book!.pageIdx = book!.pageIdx! + 1)
        : (book!.pageIdx = book!.pageIdx! - 1);
  }

  panDown(DragDownDetails e) {
    showMenu.value = false;
    if (currentTouchEvent.action != TouchEvent.ACTION_DOWN ||
        currentTouchEvent.touchPos != e.localPosition) {
      currentTouchEvent = TouchEvent(TouchEvent.ACTION_DOWN, e.localPosition);
      mPainter!.setCurrentTouchEvent(currentTouchEvent);
      canvasKey.currentContext!.findRenderObject()!.markNeedsPaint();
    }
  }

  panUpdate(DragUpdateDetails e) {
    if (!showMenu.value) {
      if (currentTouchEvent.action != TouchEvent.ACTION_MOVE ||
          currentTouchEvent.touchPos != e.localPosition) {
        currentTouchEvent = TouchEvent(TouchEvent.ACTION_MOVE, e.localPosition);
        mPainter!.setCurrentTouchEvent(currentTouchEvent);
        canvasKey.currentContext!.findRenderObject()!.markNeedsPaint();
      }
    }
  }

  panEnd(DragEndDetails e) {
    if (!showMenu.value) {
      if (currentTouchEvent.action != TouchEvent.ACTION_UP ||
          currentTouchEvent.touchPos != Offset(0, 0)) {
        currentTouchEvent =
            TouchEvent<DragEndDetails>(TouchEvent.ACTION_UP, Offset(0, 0));
        currentTouchEvent.touchDetail = e;

        mPainter!.setCurrentTouchEvent(currentTouchEvent);
        canvasKey.currentContext!.findRenderObject()!.markNeedsPaint();
      }
    }
  }

  preLoadWidget() {
    if (prePage == null) return;
    var preIdx = book!.pageIdx! - 1;
    var preKey;
    if (preIdx < 0) {
      preKey = getPageCacheKey(book!.chapterIdx! - 1, prePage!.pageOffsets - 1);
    } else {
      preKey = getPageCacheKey(book!.chapterIdx!, preIdx);
    }
    if (!homeController!.widgets.containsKey(preKey)) {
      if (prePage?.pages == null) return;
      homeController!.widgets.putIfAbsent(preKey, () => pre());
    }

    var nextIdx = book!.pageIdx! + 1;
    var nextKey;
    if (nextIdx >= curPage!.pageOffsets) {
      nextKey = getPageCacheKey(book!.chapterIdx! + 1, 0);
    } else {
      nextKey = getPageCacheKey(book!.chapterIdx!, nextIdx);
    }
    if (!homeController!.widgets.containsKey(nextKey)) {
      if (nextPage?.pages == null) return;
      homeController!.widgets.putIfAbsent(preKey, () => next());
    }
  }
}
