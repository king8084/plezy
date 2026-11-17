part of '../media_detail_screen.dart';

/// The redesigned TV show and season page (November 2026). Same rows, actions,
/// focus memory and data as the classic layout ([_buildTvDetailLayout]); what
/// changes is placement:
///
/// * the top block is anchored to the top and never slides: title or logo,
///   one information slot (the show, or the focused episode), labeled actions;
/// * season tabs sit directly above the episodes they switch;
/// * no on-screen back arrow (the remote has Back);
/// * episode cards drop the corner "E#" badge (see [TvDetailCardStyle]).
///
/// Settings > Appearance > Classic show page brings the old layout back.
extension _MediaDetailTvModernLayout on _MediaDetailScreenState {
  bool _useTvModernLayout(MediaItem metadata) =>
      (metadata.isShow || metadata.isSeason) && !SettingsService.instance.read(SettingsService.classicShowPage);

  /// Season tabs show only while the season row is the active row; the rail
  /// starts there, so an unknown active row counts as the season row.
  bool get _tvDetailSeasonTabsShown {
    final active = _tvDetailActiveHubId.value;
    return active == null || active.startsWith(_tvDetailSeasonHubIdPrefix);
  }

  /// The focused episode's still becomes the backdrop once focus rests on it
  /// for a moment (no image request per card while scrolling). Spoiler-hidden
  /// episodes and episodes without a still keep the show's backdrop.
  void _syncTvModernBackdrop() {
    _tvModernBackdropTimer?.cancel();
    final episode = _tvDetailFocusedEpisode.value;
    final hideSpoilers = SettingsService.instance.read(SettingsService.hideSpoilers);
    final still = episode?.thumbPath;
    if (episode == null || still == null || still.isEmpty || (hideSpoilers && episode.shouldHideSpoiler)) {
      _tvModernBackdropItem.value = null;
      return;
    }
    _tvModernBackdropTimer = Timer(const Duration(milliseconds: 650), () {
      if (!mounted || _tvDetailFocusedEpisode.value != episode) return;
      _tvModernBackdropItem.value = MediaItem(
        id: '${episode.id}_still',
        backend: episode.backend,
        kind: MediaKind.unknown,
        title: episode.title,
        artPath: still,
        serverId: episode.serverId,
        serverName: episode.serverName,
      );
    });
  }

  /// Focus is on a row below the episodes (cast, extras, recommendations).
  bool get _tvModernBrowsingLowerRow {
    final active = _tvDetailActiveHubId.value;
    return active != null &&
        !active.startsWith(_tvDetailSeasonHubIdPrefix) &&
        active != 'detail_episodes' &&
        !_tvDetailActionRowHasFocus.value &&
        !_tvDetailInfoFocusNode.hasFocus;
  }

  Widget _buildTvModernDetailLayout(
    BuildContext context,
    MediaItem metadata,
    KeyEventResult Function(FocusNode, KeyEvent) handleBack,
  ) {
    if (!_tvModernBackdropListening) {
      _tvModernBackdropListening = true;
      _tvDetailFocusedEpisode.addListener(_syncTvModernBackdrop);
    }
    final size = MediaQuery.sizeOf(context);
    final detailHubs = _tvDetailHubs(metadata);
    if (widget.initialEpisodeId != null && !_initialEpisodePagingDone) {
      _maybeLoadMoreForInitialEpisode();
    }
    final hideSpoilers = SettingsService.instance.read(SettingsService.hideSpoilers);
    final scale = TvLayoutConstants.scaleForSize(size);
    final scaleForInset = TvLayoutConstants.scaleForSize(size);
    // Wider TV margins: the rail is inset as a whole (its cards are not
    // clipped, so scrolled cards still slide out to the screen edge) and the
    // text above lines up with the first card.
    final railInset = 48 * scaleForInset;
    final railEdge = FocusTheme.focusBorderWidth * 2 * scaleForInset + 12 * scaleForInset;
    // The next row's heading peeks under the active one, like Home, so the
    // page reads as stacked rows.
    final activeIndex = detailHubs.indexWhere(
      (hub) => hub.id == (_tvDetailActiveHubId.value ?? _tvDetailInitialHubId(metadata)),
    );
    final hasNextRow = activeIndex >= 0 && activeIndex < detailHubs.length - 1;
    final railHeight =
        _estimateTvDetailRailHeight(Size(size.width - railInset, size.height), detailHubs) +
        (hasNextRow ? TvBrowseRailLayout.nextHubPeekHeightForScale(scaleForInset) : 0);
    if (!_tvDetailRevealed && _isTvDetailReadyToReveal(metadata)) {
      _scheduleTvDetailReveal(railHeight, focusPrimaryAction: false);
    }
    final edge = railInset + railEdge;
    final tabsHeight = _hasTvSeasonTabs ? 48 * scale : 0.0;
    final tabsGap = 6 * scale;
    final buildHiddenContent = _tvDetailRevealed || _tvDetailRouteSettled;
    final topBlockBottom = railHeight + tabsHeight + tabsGap + 20 * scale;

    final revealContent = Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: edge,
          // Upper-middle, so it reads together with the episodes below
          // instead of floating at the top; fixed, so it never slides.
          top: MediaQuery.paddingOf(context).top + (_tvModernBrowsingLowerRow ? 40 * scale : size.height * 0.26),
          width: (size.width * 0.52).clamp(0.0, 920 * scale).toDouble(),
          bottom: topBlockBottom,
          child: buildHiddenContent
              ? ListenableBuilder(
                  listenable: _tvDetailForegroundListenable,
                  builder: (context, _) =>
                      _buildTvModernTopBlock(context, metadata, hideSpoilers: hideSpoilers, scale: scale),
                )
              : const SizedBox.shrink(),
        ),
        if (buildHiddenContent && _hasTvSeasonTabs)
          Positioned(
            key: const ValueKey('tv_detail_season_tabs'),
            left: edge,
            right: edge,
            bottom: railHeight - TvBrowseRailLayout.hubStripHeightForScale(scale) + tabsGap,
            height: tabsHeight,
            child: ValueListenableBuilder<String?>(
              valueListenable: _tvDetailActiveHubId,
              builder: (context, _, _) => _tvDetailSeasonTabsShown
                  ? Align(alignment: Alignment.centerLeft, child: _buildSeasonTabs())
                  : const SizedBox.shrink(),
            ),
          ),
        if (buildHiddenContent && detailHubs.isNotEmpty)
          Positioned(
            left: railInset,
            right: 0,
            bottom: 0,
            child: TvDetailCardStyle(
              child: TvBrowseRailHeightLimit(
                maxHeight: _tvDetailActiveReadingRailLimit(size, detailHubs) ?? double.infinity,
                child: TvBrowseRail(
                  key: _tvDetailRailKey,
                  fitActiveHub: true,
                  showNextHubPeek: true,
                  hubs: detailHubs,
                  focusMemory: _hubFocusMemory,
                  iconForHub: _getTvDetailHubIcon,
                  onFocusedHubItemChanged: _handleTvDetailFocusedRailItemChanged,
                  onRefresh: (source) => unawaited(_refreshItemInPlace(source)),
                  onActiveHubChanged: _handleTvDetailHubChanged,
                  onActivateItem: _handleTvDetailRailItemActivated,
                  trailingForHub: _tvDetailTrailingState,
                  leadingItemForHub: _tvDetailLeadingItemForHub,
                  onRetryHub: _retryTvDetailHub,
                  onNavigateUp: () {
                    if (_hasTvSeasonTabs && _tvDetailSeasonTabsShown) {
                      _focusTvSeasonTabs();
                    } else {
                      _focusTvDetailActionRow();
                    }
                  },
                  onBack: _popMediaDetailIfBackNotSuppressed,
                  tallPosterScale: _tvDetailTallPosterScale,
                  widePosterScaleForHub: _tvDetailWidePosterScaleForHub,
                  initialHubId: _tvDetailInitialHubId(metadata),
                  initialItemId: _tvDetailInitialItemId(metadata),
                  episodePosterModeForHub: _tvDetailEpisodePosterModeForHub,
                  showTitleImpliedForHub: _isTvDetailEpisodeHub,
                  hideHeaderForHub: _hasTvSeasonTabs ? (hub) => hub.id.startsWith(_tvDetailSeasonHubIdPrefix) : null,
                ),
              ),
            ),
          ),
      ],
    );

    final blockSystemBack = InputModeTracker.shouldBlockSystemBack(context);
    return OverlaySheetHost(
      canPop: !blockSystemBack,
      onSystemBack: _handleMediaDetailSystemBack,
      child: Focus(
        onKeyEvent: handleBack,
        child: Scaffold(
          body: Stack(
            children: [
              ValueListenableBuilder<MediaItem?>(
                valueListenable: _tvModernBackdropItem,
                builder: (context, still, _) => TvSpotlightBackground(
                  item: still ?? metadata,
                  client: _getArtworkMediaClient(context),
                  showInfo: false,
                  localArtworkPathResolver: widget.isOffline
                      ? (path) => _offlineArtworkCandidatePath(context, path)
                      : null,
                  allowNetwork: !widget.isOffline,
                ),
              ),
              _buildTvDetailRevealGate(revealContent, handleBack),
            ],
          ),
        ),
      ),
    );
  }

  /// Title, one information slot and the actions, top-anchored so nothing
  /// moves while focus travels. The slot shows the focused episode while the
  /// episode row has focus, otherwise the show (or season).
  Widget _buildTvModernTopBlock(
    BuildContext context,
    MediaItem metadata, {
    required bool hideSpoilers,
    required double scale,
  }) {
    final theme = Theme.of(context);
    final foreground = _tvDetailForegroundColor(context);
    final muted = foreground.withValues(alpha: 0.78);
    if (_tvModernBrowsingLowerRow) {
      // Lower rows get the room: the header collapses to one line.
      return Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          key: const ValueKey('tv_modern_compact_header'),
          height: 48 * scale,
          child: Row(
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 560 * scale),
                child: Text(
                  metadata.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 34 * scale,
                    fontWeight: FontWeight.w800,
                    shadows: TvLayoutConstants.heroTextShadows,
                  ),
                ),
              ),
              SizedBox(width: 20 * scale),
              Expanded(
                child: SizedBox(height: 26 * scale, child: _buildTvDetailMetadataLine(context, metadata, scale)),
              ),
            ],
          ),
        ),
      );
    }

    final description = _tvDetailDescription(metadata, hideSpoilers: hideSpoilers);
    final focusedEpisode = _tvDetailFocusedEpisode.value;
    final genres = metadata.genres ?? const <String>[];
    final summaryFontSize = 19 * scale;
    final summaryMaxWidth = 760 * scale;

    void openDetails() => _openTvDetailsSheet(context, metadata, hideSpoilers: hideSpoilers);

    final Widget heading;
    if (metadata.isSeason) {
      final showTitle = metadata.parentTitle ?? metadata.grandparentTitle;
      heading = Column(
        key: const ValueKey('tv_modern_season_heading'),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showTitle != null && showTitle.isNotEmpty)
            Text(
              showTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: muted, fontSize: 22 * scale, fontWeight: FontWeight.w600),
            ),
          _buildDetailTitle(context, metadata.displayTitle, fontSize: 52 * scale, fontWeight: FontWeight.w800),
        ],
      );
    } else {
      heading = SizedBox(
        height: 110 * scale,
        child: LayoutBuilder(
          builder: (context, constraints) => _buildDetailLogoOrTitle(
            context,
            metadata,
            width: (560 * scale).clamp(0.0, constraints.maxWidth).toDouble(),
            height: 110 * scale,
            availableWidth: constraints.maxWidth,
            titleBuilder: (context, title) =>
                _buildDetailTitle(context, title, fontSize: 56 * scale, fontWeight: FontWeight.w800, shadowBlur: 12),
          ),
        ),
      );
    }

    final seasonProgress = metadata.isSeason ? _tvModernSeasonProgress(metadata, scale, foreground) : null;

    final info = Semantics(
      key: const ValueKey('tv_detail_information_semantics'),
      identifier: 'tv_detail_information',
      container: true,
      button: true,
      label: _tvDetailInformationSemanticLabel(metadata, description: description, genres: genres),
      hint: t.mediaMenu.viewDetails,
      onTap: openDetails,
      child: ExcludeSemantics(
        child: FocusableWrapper(
          focusNode: _tvDetailInfoFocusNode,
          onSelect: openDetails,
          onNavigateUp: () {},
          onNavigateDown: _focusTvDetailActionRow,
          onBack: _popMediaDetailIfBackNotSuppressed,
          useBackgroundFocus: true,
          disableScale: true,
          autoScroll: false,
          borderRadius: 8,
          descendantsAreFocusable: false,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: openDetails,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (focusedEpisode != null)
                  Text(
                    focusedEpisode.title ?? focusedEpisode.displayTitle,
                    key: const ValueKey('tv_detail_episode_title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 26 * scale,
                      fontWeight: FontWeight.w700,
                      shadows: TvLayoutConstants.heroTextShadows,
                    ),
                  ),
                if (focusedEpisode != null) SizedBox(height: 6 * scale),
                SizedBox(height: 26 * scale, child: _buildTvDetailMetadataLine(context, metadata, scale)),
                ?seasonProgress,
                if (description != null && description.isNotEmpty) ...[
                  SizedBox(height: 12 * scale),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: summaryMaxWidth),
                    child: Text(
                      description,
                      key: const ValueKey('tv_detail_episode_summary'),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: muted,
                        shadows: TvLayoutConstants.heroTextShadows,
                        fontSize: summaryFontSize,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    // Fixed slot height: an episode with a longer synopsis, or none, never
    // moves the actions below it.
    final slotHeight = (36 + 6 + 26 + 12 + 3 * 19 * 1.4 + (metadata.isSeason ? 18 : 0)) * scale;

    final posterPath = metadata.isSeason ? metadata.thumbPath : null;
    final hasPoster = posterPath != null && posterPath.isNotEmpty;

    // A taller lower row (cast, recommendations) shortens this area; the
    // block keeps its place and is clipped at the bottom instead of moving.
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.topLeft,
        maxHeight: double.infinity,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasPoster) ...[
              _tvModernSeasonPoster(context, posterPath, width: 150 * scale, height: 225 * scale),
              SizedBox(width: 32 * scale),
            ],
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  heading,
                  SizedBox(height: 16 * scale),
                  SizedBox(
                    height: slotHeight,
                    child: Align(alignment: Alignment.topLeft, child: info),
                  ),
                  // On a lower row (cast, extras, recommendations) the taller row
                  // needs the room; the actions come back on the way up.
                  if (!_tvModernBrowsingLowerRow) ...[
                    SizedBox(height: 18 * scale),
                    SizedBox(
                      key: const ValueKey('tv_detail_actions'),
                      height: _tvDetailActionSize * scale,
                      child: _buildActionButtons(metadata),
                    ),
                    ?_tvModernResumeNote(metadata, scale, muted),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The season page's poster beside its heading.
  Widget _tvModernSeasonPoster(
    BuildContext context,
    String posterPath, {
    required double width,
    required double height,
  }) {
    final local = _buildOfflineArtworkIfAvailable(
      context,
      artworkPaths: [posterPath],
      fit: BoxFit.cover,
      imageType: ImageType.poster,
      placeholder: (context, url) => const PlaceholderContainer(),
      errorWidget: (context, url, error) => const PlaceholderContainer(),
    );
    final Widget image;
    if (local != null) {
      image = local;
    } else if (widget.isOffline) {
      image = const PlaceholderContainer();
    } else {
      final pixelRatio = MediaImageHelper.artworkPixelRatio(context);
      final imageUrl = MediaImageHelper.getOptimizedImageUrl(
        client: _getMediaClientForMetadata(context),
        thumbPath: posterPath,
        maxWidth: width,
        maxHeight: height,
        pixelRatio: pixelRatio,
        imageType: ImageType.poster,
      );
      final (memWidth, memHeight) = MediaImageHelper.getMemCacheDimensions(
        displayWidth: (width * pixelRatio).round(),
        displayHeight: (height * pixelRatio).round(),
        imageType: ImageType.poster,
      );
      image = Image(
        image: MediaImageHelper.serverArtworkProvider(imageUrl: imageUrl, memWidth: memWidth, memHeight: memHeight),
        fit: BoxFit.cover,
        filterQuality: MediaImageHelper.artworkFilterQuality(context, ImageType.poster),
        errorBuilder: (context, error, stackTrace) => const PlaceholderContainer(),
      );
    }
    return ClipRRect(
      key: const ValueKey('tv_modern_season_poster'),
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(width: width, height: height, child: image),
    );
  }

  /// "12m left in “Come Fly with Me”" under the actions while the show has an
  /// episode in progress.
  Widget? _tvModernResumeNote(MediaItem metadata, double scale, Color color) {
    if (!metadata.isShow) return null;
    final episode = _showPlayEpisode();
    if (episode == null) return null;
    final fresh = _fresh(episode);
    final duration = fresh.durationMs;
    final offset = fresh.viewOffsetMs;
    if (duration == null || offset == null || offset <= 0 || offset >= duration) return null;
    return Padding(
      key: const ValueKey('tv_modern_resume_note'),
      padding: EdgeInsets.only(top: 12 * scale),
      child: Text(
        t.detailActions.timeLeftIn(time: formatDurationTextual(duration - offset), title: fresh.title ?? ''),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: color, fontSize: 16 * scale),
      ),
    );
  }

  /// "18 of 24 watched" with a thin bar, for the season page.
  Widget? _tvModernSeasonProgress(MediaItem season, double scale, Color foreground) {
    final total = season.leafCount;
    final watched = season.viewedLeafCount;
    if (total == null || total <= 0 || watched == null) return null;
    final fraction = (watched / total).clamp(0.0, 1.0).toDouble();
    return Padding(
      key: const ValueKey('tv_modern_season_progress'),
      padding: EdgeInsets.only(top: 8 * scale),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 240 * scale,
            height: 5 * scale,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3 * scale),
              child: LinearProgressIndicator(
                value: fraction,
                backgroundColor: foreground.withValues(alpha: 0.2),
                valueColor: AlwaysStoppedAnimation(foreground),
              ),
            ),
          ),
          SizedBox(width: 12 * scale),
          Text(
            t.detailActions.watchedOf(watched: watched, total: total),
            style: TextStyle(color: foreground.withValues(alpha: 0.78), fontSize: 16 * scale),
          ),
        ],
      ),
    );
  }
}
